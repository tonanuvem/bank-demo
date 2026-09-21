# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

FROM python:3.12.14

WORKDIR /service/

# As dependencias vem antes do codigo de proposito: editar um cenario invalida
# so a ultima camada. Na ordem anterior, trocar uma linha de um .py refazia o
# pip install inteiro -- cerca de um minuto por ajuste.
COPY requirements.txt /service/
RUN python -m pip install --upgrade pip \
 && python -m pip install -r requirements.txt

COPY . /service/

RUN chmod +x locust.sh

EXPOSE 8089 5557 5558
ENTRYPOINT [ "sleep", "infinity" ]