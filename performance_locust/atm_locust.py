# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

import os
import random

from locust import HttpUser, task, SequentialTaskSet, between
from api_urls import ApiUrls

# Ver auth_locust.py: fracao das operacoes que falha de proposito.
FALHA_PCT = int(os.getenv("FALHA_PCT") or 0)


class MyUser(HttpUser):
    host = ApiUrls["VITE_ATM_URL"]

    @task
    class MyUserTasks(SequentialTaskSet):
        wait_time = between(2, 3)

        @task
        def get_all_atms(self):
            response = self.client.post("/")
            self.atm_data = response.json()

        @task
        def get_atm_details(self):
            for atm in self.atm_data:
                self.client.get(f"/{atm['_id']}")

            # Com --falhas, pede um caixa que nao existe mais. Diferente das
            # outras recusas deste lab, esta devolve 404 -- e' o contraexemplo:
            # falha de negocio que o indicador TECNICO tambem enxerga.
            if FALHA_PCT > 0 and random.randint(1, 100) <= FALHA_PCT:
                self.client.get(
                    "/000000000000000000000000",
                    name="/{id} (caixa inexistente)",
                )
