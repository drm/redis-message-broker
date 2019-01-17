-- Author: Gerard van Helden <gerard@van-helden.name>
-- 
-- See README.md for documentation.


redis.replicate_commands();

local queue_name = ARGV[1];
if queue_name == nil then
    error("Missing queue name")
end

-- keep track of the results
local result = {}
local function log(msg)
    result[#result+1] = msg
end

local function default(key, default_value)
    local val = redis.call("GET", key)
    if not val then
        return default_value
    else
        return val
    end
end

local index_name = queue_name .. ":index"
local commit_log_key = queue_name .. ":log"
local subscribers_key = queue_name .. ":subscribers"
local subscribers = redis.call("SMEMBERS", subscribers_key)

-- drain the queue
while redis.call("LLEN", queue_name) > 0 do
    local key = redis.call("INCR", index_name)
    local value = redis.call("LPOP", queue_name)

    redis.call("HSET", commit_log_key, key, value)
end

local index = default(index_name);

-- pass messages to the subscribed queues
for _, subscriber_name in ipairs(subscribers) do
    -- read the previous offset
    local subscriber_offset_name = subscriber_name .. ":offset"
    local oldIdx = default(subscriber_offset_name, 0)

    for i = oldIdx + 1, index do
        redis.call("RPUSH", subscriber_name, redis.call("HGET", commit_log_key, i))
    end

    redis.call("SET", subscriber_offset_name, index)
    log(subscriber_name .. " is now at " .. index)
end

return result
