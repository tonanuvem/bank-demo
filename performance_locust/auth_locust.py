# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

import os
import random

from locust import HttpUser, task, SequentialTaskSet, between
from api_urls import ApiUrls
from faker import Faker

fake = Faker()

# Percentual das tentativas de login que usam senha errada de proposito.
# E' a taxa de recusa que o painel vai mostrar: 100 recusa TODAS, 20 recusa
# uma em cada cinco. Zero (o padrao) mantem o cenario como era antes.
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
            # UMA tentativa por ciclo, certa ou errada. Assim o percentual
            # pedido e' exatamente a taxa de recusa que aparece no painel --
            # com uma recusa ANTES de cada login bom, o maximo alcancavel
            # seria 50%.
            #
            # Recusar nao quebra o resto do ciclo: /profile e /logout NAO sao
            # rotas protegidas neste servico (o middleware `protect` esta
            # comentado no userRoutes.js e o generateToken tambem), entao elas
            # respondem 200 sem login nenhum -- MEDIDO. Nao ha cookie para
            # perder e nao ha cascata.
            errar = FALHA_LOGIN_PCT > 0 and random.randint(1, 100) <= FALHA_LOGIN_PCT
            self.client.post(
                "/auth",
                json={
                    "email": self.user_data["email"],
                    "password": ("senha-errada-de-proposito" if errar
                                 else self.user_data["password"]),
                },
                name=("/auth (senha errada)" if errar else "/auth"),
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