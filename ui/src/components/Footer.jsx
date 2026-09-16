/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { Row, Col, Card } from "react-bootstrap";
import "../index.css";

const Footer = () => {
  return (
    <div className="bg-dark" style={{flex: 2}}>
      <Row style={{ marginTop: "2vh", width: "100vw" }}>
        <Col md={12}>
          <Card
            className="bg-dark text-white border-0"
            style={{
              marginTop: "1.5vh",
              position: "absolute",
              bottom: 0,
              width: "100%",
            }}
          >
            <Card.Body>
              <Card.Text style={{ fontSize: "1.25vh" }}>
                <Card.Body>
                  <span>
                    <strong>Informações Regulatórias</strong>
                  </span>
                  <br />
                  <br />
                  <span>Produtos de investimento e seguros: </span>
                  1. Não são garantidos pela CMVM (Comissão Marciana de Valores
                  Mobiliários) nem por órgãos do governo marciano 2. Não
                  constituem depósito nem obrigação do banco, e não são por ele
                  garantidos 3. Estão sujeitos a riscos de mercado, incluindo a
                  possibilidade de perda do valor principal investido
                  <span>
                    Produtos e serviços de investimento são oferecidos pela FIAP
                    OTEL Bank Investimentos, nome comercial utilizado por Marte
                    Clearing Serviços Ltda. (MCS) e FIAP OTEL Bank Rede
                    Financeira Ltda., associadas à CMIP (Comissão Marciana de
                    Investimentos Planetários), corretoras independentes e
                    coligadas não bancárias do FIAP OTEL Bank S.A.
                  </span>
                  <br />
                  <span>
                    Produtos de depósito oferecidos pelo FIAP OTEL Bank S.A.,
                    associado ao FGCM (Fundo Garantidor de Créditos Marciano).
                  </span>
                  <br />
                  <span>Crédito habitacional planetário com igualdade de acesso</span>
                  <br />
                  <span>
                    MFICO é marca registrada da Martian Isaac Corporation em
                    Marte e demais corpos celestes.
                  </span>
                </Card.Body>
              </Card.Text>
            </Card.Body>
          </Card>
        </Col>
      </Row>
    </div>
  );
};

export default Footer;
