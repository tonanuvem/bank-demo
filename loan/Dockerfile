# Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

FROM python:3.12.14

RUN mkdir /service
COPY protobufs/ /service/protobufs/
COPY loan/ /service/loan/
WORKDIR /service/loan
RUN python -m pip install --upgrade pip
RUN python -m pip install -r requirements.txt

RUN python -m grpc_tools.protoc -I ../protobufs --python_out=. --grpc_python_out=. ../protobufs/loan.proto

EXPOSE 50053

ENTRYPOINT ["python", "loan.py"]
