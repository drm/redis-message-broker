# redis-message-broker
A very simple event logging and message broker model for Redis, useful for 
event sourcing solutions.

## The theory

Whenever a message enters the system, we want to notify different queues of
this message. Typically, you would use a PUB/SUB system for this (Redis has
this), but it is tedious and impractical to use that for an eventlog based
system since the log would either have to live outside of the messaging system
and/or we need some process to sit in front of the queue to log the messages.

I've looked into other messaging and logging systems and ultimately they either
have no solution for re-entrant processing, i.e. reprocessing all past messages 
(such as RabbitMQ), they are bloated or are a pain to manage (such as Kafka)
or they somehow require you to handle the atomicity of transactions yourself.

So I decided to build a simple model for this in Redis. The requirements are:

* A message queue which I can add subscribers to;
* If I want to replay a part of the log for a subset of the subscribers, I should
  be able to;
* If I add a new subscriber, I should be able to process all events from the past;
* Some blocking mechanism for triggering a backend process when a message is added
  to its queue
* It should be guaranteed that all subscribers receive all messages and all 
  messages only once

## The solution

This simple piece of lua code does the following:

* It checks the passed queue name for items;
* If there are items queued, register them in a log with a unique incremental id;
* If there are subscribers registered, add each message from the log that wasn't
  passed before to the subscriber's queue;
* Record the last index in a subscriber specific key.

Since Redis guarantees atomicity of the script, the transaction safety-ness is 
no issue.

## How to use:
* You will need some process that listens to an incoming queue using 
  `BLPOPRPUSH message_queue_incoming message_queue` and calls the script with
  `message_queue` as a parameter;
* Register subscribers by adding names to the `message_queue:subscribers` set 
  using `SADD message_queue:subscribers s1 s2 s3 ...`;
* The queues can be listened to using a `BLPOP` (or BLPOPRPUSH) for processing
  or simply poll the queue for items (using `LLEN` or `LPOP`);
* `RPUSH` an item to the `message_queue_incoming`;

## Name mapping

Assuming a queue with name `x` and two subscribers with names `q1` and `q2`:

* The incremental id value is stored in `x:index`;
* The message log is stored in a hash with name `x:log`;
* The offset for `q1` and `q2` are stored in `q1:offset` and `q2:offset` 
  respectively;

## Caveats
If the number of messages passing through the system will in any future exceed
the maximum value of an integer in redis (which is 2 to the 63rd, or 
9223372036854775807, that is: more than 9 quintillion, or roughly 10 to the 18th),
the script will throw an error. However, that would mean the messages will still 
be accumulated in the incoming queue, so no real harm done there. It's probably
best to backup stuff and start at 0 again in that case.

