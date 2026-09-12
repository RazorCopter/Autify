import asyncio
import os
import sys
import motor.motor_asyncio

async def main():
    mongo_url = os.environ.get("MONGODB_URL", "mongodb://localhost:27017")
    client = motor.motor_asyncio.AsyncIOMotorClient(mongo_url)
    db = client["autanalysis"]
    try:
        async for doc in db.audit_logs.find({}):
            print(doc)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
