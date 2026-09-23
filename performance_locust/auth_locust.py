# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

import os
import random

from locust import HttpUser, task, SequentialTaskSet, between
from api_urls import ApiUrls
from faker import Faker

fake = Faker()

# Percentual de tentativas de login que usam senha errada de proposito.
# Zero (o padrao) mantem o cenario exatamente como era antes.
#
# Sem isto o cenario NUNCA recusa um login: ele registra o usuario e em
# seguida entra com a senha correta. O SLI de recusa de login ficava
# permanentemente em zero, e o unico dado vinha de alguem errando a senha na
# tela -- um pico isolado que some em minutos. Com o painel sempre vazio, o
# aluno nao consegue distinguir "saudavel" de "quebrado".
FALHA_LOGIN_PCT = int(os.getenv("FALHA_LOGIN_PCT") or 0)


class MyUser(HttpUser):
    host = ApiUrls["VITE_USERS_URL"]

    @task
    class MyUserTasks(SequentialTaskSet):
        wait_time = between(2, 3)

        def on_start(self):
            # Create fake user data
            self.user_data = {
                "name": fake.unique.name(),
                "email": fake.unique.email(),
                "password": fake.unique.password(),
            }

            # Register
            self.client.post("/", json=self.user_data)

        @task
        def login(self):
            # A recusa vem ANTES do login bom, como uma tentativa a mais -- e
            # nao trocando a senha do login que ja' existia.
            #
            # Se o login do ciclo falhasse, o cookie nao seria emitido e
            # /profile e /logout falhariam em seguida: o cenario reportaria
            # erro em tres rotas quando so' uma foi recusada. E' o mesmo
            # defeito que ja' foi corrigido em update_profile, abaixo.
            #
            # Como efeito colateral o formato fica realista: alguem erra a
            # senha e acerta na tentativa seguinte.
            if FALHA_LOGIN_PCT > 0 and random.randint(1, 100) <= FALHA_LOGIN_PCT:
                self.client.post(
                    "/auth",
                    json={
                        "email": self.user_data["email"],
                        "password": "senha-errada-de-proposito",
                    },
                    name="/auth (senha errada)",
                )

            # Login
            self.client.post(
                "/auth",
                json={
                    "email": self.user_data["email"],
                    "password": self.user_data["password"],
                },
            )

        @task
        def get_profile(self):
            # Get Profile
            #
            # POST, nao GET: a rota e' router.route("/profile").post(...).put(...)
            # -- nao ha handler de GET, e a versao com .get() esta comentada no
            # userRoutes.js. Chamando GET, o Express respondia 404 a cada ciclo,
            # o que sozinho produzia ~25% de erro num servico saudavel.
            self.client.post("/profile", json={"email": self.user_data["email"]})

        @task
        def update_profile(self):
            # Update Profile
            #
            # A nova senha PRECISA ser guardada. Sem isso o proximo login do
            # ciclo tenta a senha antiga e recebe 401; o cookie nao e'
            # renovado e /profile e /logout falham em cascata. O cenario
            # reportava ~45% de erro que era defeito do teste, nao do banco.
            nova_senha = fake.unique.password()
            self.client.put(
                "/profile",
                json={
                    "email": self.user_data["email"],
                    "password": nova_senha,
                },
            )
            self.user_data["password"] = nova_senha

        @task
        def logout(self):
            # Logout
            self.client.post("/logout", json={"email": self.user_data["email"]})