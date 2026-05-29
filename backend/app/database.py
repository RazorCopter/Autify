from motor.motor_asyncio import AsyncIOMotorClient
import os

MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://localhost:27017")

client = AsyncIOMotorClient(MONGODB_URL)
database = client.autanalysis

# Collezioni
evaluations_collection = database.get_collection("evaluations")
patients_collection = database.get_collection("patients")
users_collection = database.get_collection("users")
scales_collection = database.get_collection("scales")
settings_collection = database.get_collection("settings")
ai_analyses_collection = database.get_collection("ai_analyses")
audit_logs_collection = database.get_collection("audit_logs")
