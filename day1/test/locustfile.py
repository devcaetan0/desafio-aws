"""
Load Testing Script - Send concurrent complaints to the API
"""

import json
import random
from locust import HttpUser, task, between

MESSAGES = [
    "Your service ate my homework and didn't even apologize!",
    "I've been waiting 3 days for my refund, this is unacceptable!",
    "The app keeps crashing every time I try to check my balance",
    "Shipping was extremely slow, package took 2 weeks",
    "The support team is completely unhelpful, nobody responds",
    "CRITICAL: The system is completely broken and nothing works!",
    "Billing charged me twice for the same order, urgent fix needed",
    "Your API documentation is worse than a fortune cookie's riddle",
    "The app crashed while processing my payment, urgent issue",
    "Customer service representative was rude and dismissive",
    "Bug in the reporting system, data is showing incorrect numbers",
    "Delivery package never arrived, tracking shows nothing",
    "The website fails during peak hours, this is ridiculous",
    "Payment processing is extremely slow, timing out constantly",
    "Mobile app has a critical bug that prevents login",
]

SEVERITIES = ["low", "medium", "high"]
CUSTOMER_IDS = [f"cust_{i:06d}" for i in range(1, 101)]


class ComplaintUser(HttpUser):
    wait_time = between(0.5, 2)

    @task(3)
    def send_complaint(self):
        """Send a single complaint to the API"""
        complaint_data = {
            "customer_id": random.choice(CUSTOMER_IDS),
            "message": random.choice(MESSAGES),
            "severity": random.choice(SEVERITIES),
        }

        headers = {"Content-Type": "application/json"}

        with self.client.post(
            "/complaints",
            json=complaint_data,
            headers=headers,
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if "complaint_id" in data and "status" in data:
                        response.success()
                    else:
                        response.failure(f"Response missing required fields: {data}")
                except json.JSONDecodeError:
                    response.failure("Invalid JSON response")
            else:
                response.failure(f"HTTP {response.status_code}: {response.text}")

    @task(1)
    def health_check(self):
        """Periodic health check of the API"""
        with self.client.get("/health", catch_response=True) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Health check failed: {response.status_code}")


class BurstyComplaintUser(HttpUser):
    """User that sends complaints in bursts"""

    wait_time = between(5, 15)

    @task
    def burst_complaints(self):
        """Send multiple complaints rapidly"""
        burst_size = random.randint(5, 20)

        for i in range(burst_size):
            complaint_data = {
                "customer_id": random.choice(CUSTOMER_IDS),
                "message": random.choice(MESSAGES),
                "severity": random.choice(SEVERITIES),
            }

            headers = {"Content-Type": "application/json"}

            with self.client.post(
                "/complaints",
                json=complaint_data,
                headers=headers,
                catch_response=True,
            ) as response:
                if response.status_code == 200:
                    try:
                        data = response.json()
                        if "complaint_id" in data:
                            response.success()
                        else:
                            response.failure("Missing complaint_id")
                    except json.JSONDecodeError:
                        response.failure("Invalid JSON")
                else:
                    response.failure(f"HTTP {response.status_code}")
