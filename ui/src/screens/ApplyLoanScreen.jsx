/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { useState, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import {
  Form,
  Button,
  Row,
  Col,
  Modal,
} from "react-bootstrap";
import FormContainer from "../components/FormContainer";
import { useDispatch, useSelector } from "react-redux";
import {
  usePostLoanMutation,
  useGetApprovedLoansMutation,
} from "../slices/loanApiSlice";
import { createLoan } from "../slices/loanSlice";
import { useGetAllAccountsMutation } from "../slices/accountApiSlice";
import { getAccounts } from "../slices/accountSlice";
import { toast } from "react-toastify";
import Loader from "../components/Loader";
import "../index.css";
import { traduzirMensagem } from "../i18n/rotulos";

const ApplyLoan = () => {
  const [validated, setValidated] = useState(false);

  const [accNo, setAccNo] = useState("");
  const [accType, setAccType] = useState("");

  const [govtId, setGovtId] = useState("");
  const [govtIdNo, setGovtIdNo] = useState("");

  const [loanType, setLoanType] = useState("");
  const [loanAmount, setLoanAmount] = useState("");

  const [intRate, setIntRate] = useState("");
  const [loanTime, setLoanTime] = useState("");

  const [isCheckboxChecked, setIsCheckboxChecked] = useState(false);
  const [loanAdded, setLoanAdded] = useState(false);

  let allAccounts = useSelector((state) => state.account.all_accounts).response;
  if (!allAccounts) {
    allAccounts = [];
  }

  const [selectedAccount, setSelectedAccount] = useState("");

  const dispatch = useDispatch();
  const navigate = useNavigate();

  const terms = {
    BaseCamp: {
      interestRate: 5.99,
      timePeriod: 10,
    },
    Rover: {
      interestRate: 6.5,
      timePeriod: 5,
    },
    PotatoFarming: {
      interestRate: 7.25,
      timePeriod: 7,
    },
    IceHome: {
      interestRate: 8.75,
      timePeriod: 15,
    },
    Rocket: {
      interestRate: 9.99,
      timePeriod: 20,
    },
  };

  const [postLoanAPI, { isLoading }] = usePostLoanMutation();
  const [getAllAccounts, { isLoading: isLoading1 }] =
    useGetAllAccountsMutation();

  const { userInfo } = useSelector((state) => state.auth);

  const submitHandler = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    setValidated(true);

    const form = e.currentTarget;
    if (form.checkValidity()) {
      try {
        const data_loan = new FormData();
        data_loan.append("name", userInfo.name);
        data_loan.append("email", userInfo.email);
        data_loan.append("account_number", accNo);
        data_loan.append("account_type", accType);
        data_loan.append("govt_id_number", govtIdNo);
        data_loan.append("govt_id_type", govtId);
        data_loan.append("loan_type", loanType);
        data_loan.append("loan_amount", loanAmount);
        data_loan.append("interest_rate", intRate);
        data_loan.append("time_period", loanTime);
        const res = await postLoanAPI(data_loan).unwrap();
        console.log(res);
        dispatch(createLoan(res));
        toast.success("Parabéns! Seu empréstimo foi aprovado!", {
          className: "toast-container-custom",
          autoClose: 500,
          hideProgressBar: true,
          closeOnClick: true,
          pauseOnHover: true,
          draggable: true,
          progress: undefined,
          theme: "dark",
        });
        navigate("/loan");
        setLoanAdded(true);
      } catch (err) {
        console.log(err);
        toast.error(traduzirMensagem(err?.data?.message || err.error), {
          className: "toast-container-custom",
          autoClose: 500,
          hideProgressBar: true,
          closeOnClick: true,
          pauseOnHover: true,
          draggable: true,
          progress: undefined,
          theme: "dark",
        });
      }
    }
  };

  const [showModal, setShowModal] = useState(false);

  const handleModalOpen = () => {
    setShowModal(true);
  };

  const handleModalClose = () => {
    setShowModal(false);
  };

  const fetchAccounts = async () => {
    const data = new FormData();
    data.append("email_id", userInfo.email);
    const res = await getAllAccounts(data).unwrap();
    dispatch(getAccounts(res));
  };

  useEffect(() => {
    try {
      fetchAccounts();
    } catch (err) {
      console.log(err);
      toast.error("Erro ao carregar as contas!", {
        className: "toast-container-custom",
        autoClose: 500,
        hideProgressBar: true,
        closeOnClick: true,
        pauseOnHover: true,
        draggable: true,
        progress: undefined,
        theme: "dark",
      });
    }
  }, []);

  return (
    <FormContainer>
      <h4
        className="bg-light mx-3"
        style={{
          textAlign: "center",
          paddingTop: "2vh",
          paddingBottom: "2vh",
        }}
      >
        Solicitação de Empréstimo
      </h4>
      {isLoading ? (
        <Loader />
      ) : (
        <Form noValidate validated={validated} onSubmit={submitHandler}>
          <Row className="mt-4">
            <Col md={6}>
              <Form.Group className="my-3" controlId="name">
                <Form.Label>Nome</Form.Label>
                <Form.Control
                  type="text"
                  placeholder="Informe seu nome"
                  value={userInfo.name}
                  disabled
                  required
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
                  required
                ></Form.Control>
              </Form.Group>
            </Col>
          </Row>

          <Row>
            <Col md={4}>
              <Form.Group className="my-3" controlId="acc_type">
                <Form.Label>Tipo de conta</Form.Label>
                <Form.Select
                  required
                  value={accType}
                  multiple={false}
                  onChange={(e) => setAccType(e.target.value)}
                  aria-label="Selecione o tipo de conta"
                  disabled={accType ? true : false}
                >
                  <option value="">Selecione o tipo de conta</option>
                  <option value="Savings">Poupança</option>
                  <option value="Checking">Conta Corrente</option>
                  <option value="Investment">Investimento</option>
                  <option value="Money Market">Fundo DI</option>
                </Form.Select>
              </Form.Group>
            </Col>
            <Col md={8}>
              <Form.Group className="my-3" controlId="acc_no">
                <Form.Label>Número da conta</Form.Label>
                <Form.Select
                  required
                  value={accNo ? accNo : "Select Account"}
                  onChange={(e) => {
                    const selectedAccountNumber = e.target.value;
                    const selectedAccount = allAccounts.find(
                      (account) =>
                        account.account_number === selectedAccountNumber
                    );
                    setAccNo(selectedAccountNumber);
                    setAccType(
                      selectedAccount ? selectedAccount.account_type : null
                    );
                    setGovtId(
                      selectedAccount
                        ? selectedAccount.government_id_type
                        : null
                    );
                    setGovtIdNo(
                      selectedAccount ? selectedAccount.govt_id_number : null
                    );
                  }}
                  aria-label="Selecione a conta"
                >
                  <option value="">Selecione a conta</option>
                  {allAccounts.map((account) => (
                    <option value={account.account_number}>
                      {account.account_number}
                    </option>
                  ))}
                </Form.Select>
              </Form.Group>
            </Col>
          </Row>

          <Row>
            <Col md={4}>
              <Form.Group className="my-3" controlId="govt_id">
                <Form.Label>Tipo de documento</Form.Label>
                <Form.Select
                  required
                  value={govtId}
                  multiple={false}
                  onChange={(e) => setGovtId(e.target.value)}
                  aria-label="Selecione o tipo de documento"
                  disabled={govtId ? true : false}
                >
                  <option value="">Selecione o documento</option>
                  <option value="Passport">Passaporte</option>
                  <option value="DriverLicense">CNH</option>
                  <option value="AadharCard">CPF</option>
                </Form.Select>
              </Form.Group>
            </Col>
            <Col md={8}>
              <Form.Group className="my-3" controlId="govt_id_no">
                <Form.Label>Número do documento</Form.Label>
                <Form.Control
                  required
                  type="text"
                  placeholder="Informe o número do documento"
                  value={govtIdNo}
                  onChange={(e) => setGovtIdNo(e.target.value)}
                  disabled={govtIdNo ? true : false}
                />
              </Form.Group>
            </Col>
          </Row>

          <Row>
            <Col md={6}>
              <Form.Group className="my-3" controlId="loan_type">
                <Form.Label>Tipo de empréstimo</Form.Label>
                <Form.Select
                  required
                  value={loanType}
                  multiple={false}
                  onChange={(e) => {
                    const selectedLoanType = e.target.value;
                    setIntRate(terms[selectedLoanType].interestRate);
                    setLoanTime(terms[selectedLoanType].timePeriod);
                    setLoanType(e.target.value);
                  }}
                  aria-label="Selecione o tipo de empréstimo"
                >
                  <option value="">Selecione o tipo de empréstimo</option>
                  <option value="BaseCamp">Acampamento Base</option>
                  <option value="Rover">Rover</option>
                  <option value="PotatoFarming">Plantação de Batatas</option>
                  <option value="IceHome">Casa de Gelo</option>
                  <option value="Rocket">Foguete</option>
                </Form.Select>
              </Form.Group>
            </Col>
            <Col md={6}>
              <Form.Group className="my-3" controlId="loan_amount">
                <Form.Label>Valor do empréstimo</Form.Label>
                <Form.Control
                  type="number"
                  min="0"
                  required
                  placeholder="Informe o valor do empréstimo"
                  value={loanAmount}
                  onChange={(e) => setLoanAmount(e.target.value)}
                  onWheel={(e) => e.target.blur()}
                ></Form.Control>
              </Form.Group>
            </Col>
          </Row>

          <Row>
            <Col md={6}>
              <Form.Group className="my-3" controlId="loan_type">
                <Form.Label>Taxa de juros</Form.Label>
                <Form.Control
                  value={intRate}
                  type="number"
                  min="5"
                  required
                  disabled
                  placeholder="Selecione o tipo de empréstimo"
                  onWheel={(e) => e.target.blur()}
                  onChange={(e) => setIntRate(e.target.value)}
                  aria-label="Selecione o tipo de empréstimo"
                ></Form.Control>
              </Form.Group>
            </Col>
            <Col md={6}>
              <Form.Group className="my-3" controlId="loan_amount">
                <Form.Label>Prazo</Form.Label>
                <Form.Control
                  type="number"
                  min="0"
                  required
                  disabled
                  placeholder="Selecione o tipo de empréstimo"
                  value={loanTime}
                  onChange={(e) => setLoanTime(e.target.value)}
                  onWheel={(e) => e.target.blur()}
                ></Form.Control>
              </Form.Group>
            </Col>
          </Row>

          <Row>
            <Col>
              <div style={{ display: "flex", alignItems: "center" }}>
                <Form.Group controlId="checkbox">
                  <Form.Check
                    type="checkbox"
                    checked={isCheckboxChecked}
                    onChange={(e) => setIsCheckboxChecked(e.target.checked)}
                    required
                  />
                </Form.Group>
                <div
                  onClick={handleModalOpen}
                  style={{ textDecoration: "underline", color: "blue" }}
                >
                  Termos e Condições
                </div>
                <Modal
                  show={showModal}
                  onHide={handleModalClose}
                  centered
                  size="xl"
                >
                  <Modal.Header closeButton>
                    <Modal.Title>Termos e Condições</Modal.Title>
                  </Modal.Header>
                  <Modal.Body>
                    <p>
                      Bem-vindo ao FIAP OTEL Bank! Ao solicitar um empréstimo
                      conosco, você concorda com os termos e condições a seguir:
                    </p>

                    <h3>1. Elegibilidade</h3>
                    <p>
                      Para solicitar um empréstimo no FIAP OTEL Bank, você precisa
                      atender a alguns critérios de elegibilidade, entre eles: ser
                      residente em Marte, ter no mínimo 21 anos e cumprir os
                      padrões de análise de crédito definidos pelo FIAP OTEL Bank.
                      Documentos e informações adicionais podem ser solicitados
                      durante o processo.
                    </p>

                    <h3>2. Condições do Empréstimo</h3>
                    <p>
                      As condições do empréstimo, incluindo valor, taxa de juros,
                      prazo de pagamento e eventuais tarifas, serão apresentadas
                      durante a solicitação. É importante ler e entender essas
                      condições antes de aceitar a proposta. Qualquer alteração
                      será comunicada com a devida antecedência.
                    </p>

                    <h3>3. Pagamento</h3>
                    <p>
                      Como tomador, você é responsável por pagar as parcelas nos
                      prazos acordados no contrato. O atraso pode gerar encargos,
                      multas e restrições no seu histórico de crédito. Organize
                      suas finanças e garanta saldo suficiente para as parcelas.
                    </p>

                    <h3>4. Inadimplência</h3>
                    <p>
                      Em caso de inadimplência, o FIAP OTEL Bank poderá tomar as
                      medidas necessárias para recuperar o valor em aberto,
                      incluindo registro em órgãos de proteção ao crédito, ações
                      judiciais e contratação de empresas de cobrança. Em caso de
                      dificuldade financeira, procure o FIAP OTEL Bank para buscar
                      alternativas e evitar a inadimplência.
                    </p>

                    <p>
                      Ao solicitar um empréstimo no FIAP OTEL Bank, você declara
                      que leu, entendeu e concorda com estes Termos e Condições.
                      Em caso de dúvidas, fale com nossa equipe de atendimento.
                    </p>
                  </Modal.Body>
                  <Modal.Footer>
                    <Button variant="dark" onClick={handleModalClose}>
                      Concordo
                    </Button>
                  </Modal.Footer>
                </Modal>
              </div>
            </Col>
          </Row>

          <Row>
            <Col md={6}>
              <Button
                style={{ width: "100%" }}
                type="submit"
                variant="dark"
                className="mt-5 mr-3"
              >
                Solicitar
              </Button>
            </Col>
            <Col md={6}>
              <Link to="/loan">
                <Button
                  style={{ width: "100%" }}
                  variant="dark"
                  className="mt-5"
                >
                  Cancelar
                </Button>
              </Link>
            </Col>
          </Row>
        </Form>
      )}
    </FormContainer>
  );
};

export default ApplyLoan;
