import asyncio
import motor.motor_asyncio
import sys

async def main():
    client = motor.motor_asyncio.AsyncIOMotorClient("mongodb://admin:S@f3Passw0rd!@localhost:27017/")
    db = client["autify"]
    try:
        async for doc in db.audit_logs.find({}):
            print(doc)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
