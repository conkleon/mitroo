import Redis from "ioredis";

const redisUrl =
  process.env.NODE_ENV === "production"
    ? process.env.REDIS_URL
    : process.env.REDIS_URL_DEV || process.env.REDIS_URL;

const redis = new Redis(redisUrl || "redis://localhost:6379");

redis.on("connect", () => console.log("🔗 Redis connected"));
redis.on("error", (err) => console.error("Redis error:", err));

export default redis;
