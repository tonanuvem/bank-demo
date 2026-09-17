/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { Container, Row, Col } from "react-bootstrap";

const FormContainer = ({ children, position }) => {
  return (
    <Container>
      {position === "left" ? (
        <>
          <Row className="justify-content-md bg-light" style={{ margin: "5vh"}}>
            <Col
              md={5}
              className="rounded border p-5"
              style={{ margin: "5vh" }}
            >
              {children}
            </Col>

            <Col
              md={6}
              className="rounded p-5"
              style={{ margin: "5vh" }}
            >
              <Row>
                <Col md={12} className="p-5">
                  <h1 className="text-center">Bônus de $100 por nossa conta!</h1>
                  <p className="text-center">
                    Abra uma conta elegível, faça depósitos eletrônicos
                    qualificados e ganhe $100 de bônus.
                  </p>
                </Col>
              </Row>
              <Row>
                <Col md={12} className="p-5">
                  <img
                    src="./src/assets/card.webp"
                    alt="Cartão FIAP OTEL Bank"
                    className="img-fluid"
                  />
                </Col>
              </Row>
            </Col>
          </Row>
        </>
      ) : (
        <Row className="justify-content-md-center mt-5">
          <Col md={6} className="card p-5">
            {children}
          </Col>
        </Row>
      )}
    </Container>
  );
};

export default FormContainer;
