# Extrato (/transaction/history) isolado.
#
# O transaction_locust.py ja' chama esta rota, mas junto com transferencia
# interna e Zelle: no total ela e' menos de um terco das requisicoes. Para
# medir a jornada de extrato sozinha -- ou dar carga so' nela -- a proporcao
# precisa ser outra.
#
# A montagem (duas contas e uma transferencia) roda uma vez, no on_start, so'
# para o extrato nao voltar vazio. Depois disso o laco chama EXCLUSIVAMENTE
# /history.

from locust import HttpUser, task, SequentialTaskSet, between
from api_urls import ApiUrls
import random
from faker import Faker

fake = Faker()


class MyUser(HttpUser):
    host = ApiUrls["VITE_TRANSFER_URL"]

    @task
    class MyUserTasks(SequentialTaskSet):
        wait_time = between(1, 2)

        def on_start(self):
            accounts_host = ApiUrls["VITE_ACCOUNTS_URL"]

            usuario = {
                "name": fake.unique.name(),
                "email_id": fake.unique.email(),
                "account_type": "Checking",
                "government_id_type": random.choice(
                    ["Driver's License", "Passport", "SSN"]
                ),
                "govt_id_number": fake.unique.ssn(),
                "address": fake.unique.address(),
            }
            formulario = {"Content-Type": "application/x-www-form-urlencoded"}

            self.client.post(
                f"{accounts_host}/create", data=usuario, headers=formulario)

            # Uma segunda conta do MESMO dono: e' entre elas que sai a
            # transferencia que da' conteudo ao extrato.
            usuario["account_type"] = "Savings"
            self.client.post(
                f"{accounts_host}/create", data=usuario, headers=formulario)

            resposta = self.client.post(
                f"{accounts_host}/allaccounts",
                data={"email_id": usuario["email_id"]},
                headers=formulario,
            )
            self.contas = [
                c["account_number"] for c in resposta.json()["response"]
            ]

            if len(self.contas) >= 2:
                self.client.post(
                    "/",
                    data={
                        "sender_account_number": self.contas[0],
                        "receiver_account_number": self.contas[1],
                        "amount": fake.random_int(min=1, max=3),
                        "reason": "Montagem do extrato",
                    },
                    headers=formulario,
                )

        @task
        def extrato(self):
            if not self.contas:
                return
            self.client.post(
                "/history",
                data={"account_number": self.contas[0]},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
