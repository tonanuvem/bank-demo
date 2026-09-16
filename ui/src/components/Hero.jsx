/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { Container, Card, Button, Col, Row } from "react-bootstrap";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { LinkContainer } from "react-router-bootstrap";
import {
  faMoneyBillWave,
  faShieldAlt,
  faRocket,
} from "@fortawesome/free-solid-svg-icons";

const Hero = () => {
  return (
    <div className="py-5">
      <Container className="d-flex justify-content-center">
        <Card className="p-5 d-flex flex-column align-items-center hero-card w-75">
          <h1 className="text-center mb-4">
            <span style={{ fontSize: "4vh", fontWeight: "bold" }}>
              Bem-vindo ao FIAP OTEL Bank
            </span>
          </h1>
          <p style={{ fontSize: "2vh", textAlign: "center" }}>
            Cuide das suas finanças marcianas com o FIAP OTEL Bank - seu parceiro
            financeiro de confiança no Planeta Vermelho. Conheça nossas soluções
            bancárias inovadoras, aproveite a segurança de ponta e impulsione
            seus projetos marcianos com empréstimos e investimentos competitivos.
          </p>
          <div className="d-flex mt-4 mb-4">
            <LinkContainer to="/login">
              <Button variant="dark" className="me-5 px-5 py-2">
                <span style={{ fontSize: "2vh" }}>Entrar</span>
              </Button>
            </LinkContainer>
            <LinkContainer to="/register">
              <Button variant="dark" className="me-5 px-5 py-2">
                <span style={{ fontSize: "2vh" }}>Cadastrar</span>
              </Button>
            </LinkContainer>
          </div>
          <div className="d-flex justify-content-around mt-5">
            <Row>
              <Col md={4}>
                <Card className="text-center border-0">
                  <FontAwesomeIcon
                    icon={faMoneyBillWave}
                    className="display-3 my-3"
                  />
                  <Card.Body>
                    <Card.Title>Soluções Bancárias Flexíveis</Card.Title>
                    <Card.Text>
                      Uma linha completa de produtos e serviços bancários
                      feita sob medida para as suas necessidades marcianas.
                    </Card.Text>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={4}>
                <Card className="text-center border-0">
                  <FontAwesomeIcon
                    icon={faShieldAlt}
                    className="display-3 my-3"
                  />
                  <Card.Body>
                    <Card.Title>Segurança de Ponta</Card.Title>
                    <Card.Text>
                      Fique tranquilo: seus bens marcianos estão protegidos
                      com a gente.
                    </Card.Text>
                  </Card.Body>
                </Card>
              </Col>
              <Col md={4}>
                <Card className="text-center border-0">
                  <FontAwesomeIcon icon={faRocket} className="display-3 my-3" />
                  <Card.Body>
                    <Card.Title>Projetos Marcianos</Card.Title>
                    <Card.Text>
                      Realize seus sonhos marcianos com nossos empréstimos e
                      oportunidades de investimento.
                    </Card.Text>
                  </Card.Body>
                </Card>
              </Col>
            </Row>
          </div>
        </Card>
      </Container>
    </div>
  );
};

export default Hero;
