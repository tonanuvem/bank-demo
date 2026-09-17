/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import {
  Button,
  Row,
  Col,
  Card, 
  Badge,
} from "react-bootstrap";
import { useDispatch, useSelector } from "react-redux";
import {
  useGetApprovedLoansMutation,
} from "../slices/loanApiSlice";
import { storeLoanHistory } from "../slices/loanSlice";
import { toast } from "react-toastify";
import Loader from "../components/Loader";
import { traduzir, tiposDeEmprestimo } from "../i18n/rotulos";
import "../index.css";

const CustomCard = ({ title, text, icon, link }) => {
  return (
    <Card
      className="custom-card"
      style={{
        marginTop: "1.25vh",
      }}
    >
      <Card.Body>
        <Card.Title style={{ fontSize: "2vh" }} className="text-center">
          <strong>{title}</strong>
        </Card.Title>
        <Card.Text style={{ fontSize: "1.25vh" }} className="text-center">
          {text}
        </Card.Text>
      </Card.Body>
      <style>
        {`
                .custom-card:hover .card-body{
                  box-shadow: 0 10px 10px rgba(0, 0, 0, 0.5);
                }
                .custom-card:hover .position-absolute{
                  box-shadow: 0 10px 10px rgba(0, 0, 0, 0.5);
                }
              `}
      </style>
    </Card>
  );
};

const LoanScreen = () => {

  const [loanAdded, setLoanAdded] = useState(false);

  const loanInfo = useSelector((state) => state.loan.loan_history).response;

  let allAccounts = useSelector((state) => state.account.all_accounts).response;
  if (!allAccounts) {
    allAccounts = [];
  }

  const dispatch = useDispatch();
  const navigate = useNavigate();

  const [loanHistoryAPI, { isLoading: isLoading2 }] =
    useGetApprovedLoansMutation();

  const { userInfo } = useSelector((state) => state.auth);

  const fetchLoans = async () => {
    const data = new FormData();
    data.append("email", userInfo.email);
    const res = await loanHistoryAPI(data).unwrap();
    console.log(res);
    dispatch(storeLoanHistory(res));
  };

  useEffect(() => {
    try {
      fetchLoans();
    } catch (err) {
      console.log(err);
      toast.error("Erro ao carregar os empréstimos!", {
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
  }, [loanAdded]);

  return (
    <Row fluid style={{ overflowY: "auto" }}>
      <Col md={4} className="mt-5">
        <div
          style={{
            fontSize: "2.5vh",
            backgroundColor: "#e9ecef",
            marginBottom: "3vh",
          }}
          className="card text-center p-3"
        >
          Opções de empréstimo para você
        </div>
        <CustomCard
          title="Acampamento Base"
          text={
            <>
              Taxa de juros: 5,99% · Prazo: 10 anos <br />
              <Badge
                bg="success"
                style={{
                  position: "absolute",
                  top: "1rem",
                  right: "1rem",
                }}
              >
                Elegível
              </Badge>
            </>
          }
        />
        <CustomCard
          title="Rover"
          text={
            <>
              Taxa de juros: 6,5% · Prazo: 5 anos <br />
              <Badge
                bg="success"
                style={{
                  position: "absolute",
                  top: "1rem",
                  right: "1rem",
                }}
              >
                Elegível
              </Badge>
            </>
          }
        />
        <Row>
          <Col md={3} />
          <Col md={6}>
            <Button
              style={{ width: "100%" }}
              variant="dark"
              className="mt-5"
              onClick={() => navigate("/new-loan")}
            >
              Solicite aqui!
            </Button>
          </Col>
          <Col md={3} />
        </Row>
      </Col>

      <Col md={1} />

      <Col md={6} className="mt-5">
        {loanInfo ? (
          loanInfo.length > 0 ? (
            <div>
              <div
                style={{
                  fontSize: "2.5vh",
                  backgroundColor: "#e9ecef",
                  marginBottom: "3vh",
                }}
                className="card text-center p-3"
              >
                Empréstimos contratados
              </div>
              {loanInfo.map((loan) => (
                <CustomCard
                  title={`Empréstimo ${traduzir(loan.loan_type, tiposDeEmprestimo)} de $${loan.loan_amount}`}
                  text={
                    <>
                      Taxa de juros: {loan.interest_rate}% · Prazo:
                      {loan.time_period} anos <br />
                      Conta: {loan.account_number}
                    </>
                  }
                />
              ))}
            </div>
          ) : (
            <div>
              <div
                style={{
                  fontSize: "2.5vh",
                  backgroundColor: "#e9ecef",
                  marginBottom: "3vh",
                }}
                className="card text-center p-3"
              >
                Empréstimos contratados
              </div>
              <h3 className="mt-5" style={{ textAlign: "center" }}>
                Você ainda não tem empréstimos aprovados
              </h3>
            </div>
          )
        ) : (
          <Loader />
        )}
      </Col>
    </Row>
  );
};

export default LoanScreen;
