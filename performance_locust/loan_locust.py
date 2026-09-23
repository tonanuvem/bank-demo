# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

from locust import HttpUser, task, SequentialTaskSet, between
from api_urls import ApiUrls
import os
import random
from faker import Faker

fake = Faker()

# Ver auth_locust.py: fracao das operacoes que falha de proposito.
FALHA_PCT = int(os.getenv("FALHA_PCT") or 0)


class MyUser(HttpUser):
    host = ApiUrls["VITE_LOAN_URL"]

    @task
    class MyUserTasks(SequentialTaskSet):
        wait_time = between(2, 3)

        def on_start(self):
            account_host = ApiUrls["VITE_ACCOUNTS_URL"]
            # Create fake account data
            self.user_data = {
                "name": fake.unique.name(),
                "email_id": fake.unique.email(),
                "account_type": random.choice(
                    ["Checking", "Savings", "Money Market", "Investment"]
                ),
                "government_id_type": random.choice(
                    ["Driver's License", "Passport", "SSN"]
                ),
                "govt_id_number": fake.unique.ssn(),
                "address": fake.unique.address(),
            }

            # Create a new account
            self.client.post(
                f"{account_host}/create",
                data=self.user_data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )

            # Get all accounts
            response = self.client.post(
                f"{account_host}/allaccounts",
                data={"email_id": self.user_data["email_id"]},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            self.account_number = response.json()["response"][0]["account_number"]

        @task
        def apply(self):
            self.user_data["email"] = self.user_data["email_id"]
            self.user_data["govt_id_type"] = self.user_data["government_id_type"]
            self.user_data["account_number"] = self.account_number
            self.user_data["interest_rate"] = random.randint(1, 10)
            self.user_data["time_period"] = random.randint(1, 10)
            # A regra que ja' existe no servico: valor menor que 1 e' recusado.
            # HTTP 200 com "Loan Rejected" -- credito negado, receita nao
            # realizada, e nenhuma metrica enxerga.
            recusar = FALHA_PCT > 0 and random.randint(1, 100) <= FALHA_PCT
            self.user_data["loan_amount"] = 0 if recusar else random.randint(1000, 10000)
            self.user_data["loan_type"] = random.choice(
                ["Base Camp", "Rover", "Potato Farming", "Ice Home", "Rocker"]
            )
            self.client.post(
                "/",
                data=self.user_data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                name="/ (credito negado)" if recusar else "/",
            )

        @task
        def history(self):
            self.client.post(
                "/history",
                data={"email": self.user_data["email_id"]},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
