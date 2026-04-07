import os
import sqlite3
import logging

# Credentials are now retrieved from environment variables
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")

def handle_intake(patient_data):
    # Fix: SQL Injection (parameterized query)
    db = sqlite3.connect("patients.db")
    cursor = db.cursor()
    query = "SELECT * FROM patients WHERE name = ?"
    cursor.execute(query, (patient_data['name'],))
    
    # Fix: PHI Logging (using patient_id or generic message)
    patient_id = patient_data.get('id', 'unknown')
    logging.info(f"Processing intake for patient_id: {patient_id}")
    
    return cursor.fetchone()
