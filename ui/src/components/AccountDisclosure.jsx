import Card from "react-bootstrap/Card";

const AccountDisclosure = () => {
  return (
    <Card
      style={{
        marginTop: "1.5vh",
      }}
    >
      <Card.Body>
        <Card.Text style={{ fontSize: "1vh" }}>
          <Card.Body className="text-muted">
            <span>
              <strong>Informações Regulatórias</strong>
            </span>
            <br />
            <br />
            <span>Produtos de investimento e seguros:</span>
            <br />
            <ul>
              <li>
                Não são garantidos pela CMVM (Comissão Marciana de Valores
                Mobiliários) nem por qualquer órgão do governo marciano
              </li>
              <li>
                Não constituem depósito nem obrigação do banco ou de suas
                coligadas, e não são por eles garantidos
              </li>
              <li>
                Estão sujeitos a riscos de mercado, incluindo a possibilidade
                de perda do valor principal investido
              </li>
            </ul>
            <span>
              Produtos e serviços de investimento são oferecidos pela FIAP OTEL
              Bank Investimentos, nome comercial utilizado por Marte Clearing
              Serviços Ltda. (MCS) e FIAP OTEL Bank Rede Financeira Ltda.,
              associadas à CMIP (Comissão Marciana de Investimentos
              Planetários), corretoras independentes e coligadas não bancárias
              do FIAP OTEL Bank S.A.
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
              No FIAP OTEL Bank, temos o compromisso de promover a
              sustentabilidade e apoiar iniciativas ambientais em todas as
              nossas operações. Junte-se a nós na missão de construir um futuro
              mais verde e sustentável para todos os habitantes de Marte.
            </span>
            <br />
            <span>
              Para dúvidas sobre nossos produtos e serviços, ou para saber mais
              sobre nosso compromisso com a sustentabilidade, visite nosso site
              ou fale com a equipe de atendimento.
            </span>
            <br />
            <br />
            <span>© 2023 FIAP OTEL Bank. Todos os direitos reservados.</span>
          </Card.Body>
        </Card.Text>
      </Card.Body>
    </Card>
  );
};

export default AccountDisclosure;
