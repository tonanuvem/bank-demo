/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { useState } from "react";
import { Link } from "react-router-dom";
import { Form, Button, Row, Col } from "react-bootstrap";
import FormContainer from "../components/FormContainer";
import Loader from "../components/Loader";
import { useSelector } from "react-redux";

const AccInfoScreen = () => {
  let currentAccount = useSelector((state) => state.account.current_account);
  const { userInfo } = useSelector((state) => state.auth);

  if (!currentAccount) {
    currentAccount = {
      account_type: "",
      account_number: "",
      balance: "",
      address: "",
      govtId: "",
      govtIdNo: "",
    };
  }

  const [accType, setAccType] = useState(currentAccount.account_type);
  const [accNo, setAccNo] = useState(currentAccount.account_number);
  const [balance, setBalance] = useState(currentAccount.balance);
  const [address, setAddress] = useState(currentAccount.address);
  const [govtId, setGovtId] = useState(currentAccount.government_id_type);
  const [govtIdNo, setGovtIdNo] = useState(currentAccount.govt_id_number);

  const isLoading = false;

  const submitHandler = async (e) => {
    e.preventDefault();
    // try {
    //   const res = await login({ email, password }).unwrap();
    //   dispatch(setCredentials({ ...res }));
    //   toast.success('Successfully logged in!')
    //   navigate('/');
    // } catch (err) {
    //   toast.error(err?.data?.message || err.error);
    // }
  };

  return (
    <FormContainer>
      <h4
        className="bg-light mx-3"
        style={{
          textAlign: "center",
          paddingTop: "2vh",
          paddingBottom: "2vh",
          marginBottom: "3vh",
        }}
      >
        Dados da conta
      </h4>

      <Form>
        <Row>
          <Col md={4}>
            <Form.Group className="my-3" controlId="acc_no">
              <Form.Label>Tipo de conta</Form.Label>
              <Form.Control
                type="text"
                value={accType ? accType : "Error"}
                disabled
              ></Form.Control>
            </Form.Group>
          </Col>
          <Col md={8}>
            <Form.Group className="my-3" controlId="acc_no">
              <Form.Label>Número da conta</Form.Label>
              <Form.Control
                type="text"
                placeholder="Informe o número da conta"
                value={accNo ? accNo : "Error"}
                disabled
              ></Form.Control>
            </Form.Group>
          </Col>
        </Row>

        <Row className="m3-4">
          <Col md={6}>
            <Form.Group className="my-3" controlId="name">
              <Form.Label>Nome</Form.Label>
              <Form.Control
                type="text"
                placeholder="Informe seu nome"
                value={userInfo.name}
                disabled
              ></Form.Control>
            </Form.Group>
          </Col>
          <Col md={6}>
            <Form.Group className="my-3" controlId="email">
              <Form.Label>E-mail</Form.Label>
              <Form.Control
                type="email"
                placeholder="Informe seu e-mail"
                value={userInfo.email}
                disabled
              ></Form.Control>
            </Form.Group>
          </Col>
        </Row>

        <Row>
          <Col md={6}>
            <Form.Group className="my-3" controlId="govt_id">
              <Form.Label>Documento</Form.Label>
              <Form.Select
                value={govtId ? govtId : "Error"}
                multiple={false}
                disabled
              >
                <option value="">Selecione o documento</option>
                <option value="Passport">Passaporte</option>
                <option value="Driver License">CNH</option>
                <option value="Aadhar Card">CPF</option>
              </Form.Select>
            </Form.Group>
          </Col>
          <Col md={6}>
            <Form.Group className="my-3" controlId="govt_id_no">
              <Form.Label>Número do documento</Form.Label>
              <Form.Control
                type="text"
                placeholder="Informe o número do documento"
                value={govtIdNo ? govtIdNo : "Error"}
                disabled
              />
            </Form.Group>
          </Col>
        </Row>

        <Row>
          <Col md={4}>
            <Form.Group className="my-3" controlId="balance">
              <Form.Label>Saldo</Form.Label>
              <Form.Control
                type="text"
                placeholder="Informe o saldo"
                value={balance ? `$ ${balance}` : "Error"}
                disabled
              ></Form.Control>
            </Form.Group>
          </Col>
          <Col md={8}>
            <Form.Group className="my-3" controlId="address">
              <Form.Label>Endereço</Form.Label>
              <Form.Control
                type="text"
                placeholder="Informe seu endereço residencial"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
              ></Form.Control>
            </Form.Group>
          </Col>
        </Row>

        <Row className="my-4">
          <Col md={6}>
            <Button
              disabled={isLoading}
              style={{ width: "100%" }}
              type="submit"
              onClick={submitHandler}
              variant="dark"
              className="mt-3 mr-3"
            >
              Salvar
            </Button>
          </Col>
          <Col md={6}>
            <Link to="/">
              <Button
                disabled={isLoading}
                style={{ width: "100%" }}
                type="submit"
                variant="dark"
                className="mt-3 mr-3"
              >
                Voltar
              </Button>
            </Link>
          </Col>
        </Row>
      </Form>

      {isLoading && <Loader />}
    </FormContainer>
  );
};

export default AccInfoScreen;
