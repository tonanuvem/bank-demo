import { Modal } from "react-bootstrap";

const TermsAndConditionsModal = () => {
  return (
    <>
      <Modal.Header closeButton>
        <Modal.Title>Termos e Condições</Modal.Title>
      </Modal.Header>
      <Modal.Body>
        <p>
          Bem-vindo ao FIAP OTEL Bank! Ao abrir uma conta conosco, você
          concorda com os termos e condições a seguir:
        </p>
        <h3>1. Elegibilidade</h3>
        <p>
          Para abrir uma conta no FIAP OTEL Bank, você precisa ser residente
          em Marte e ter pelo menos 18 anos. Podemos solicitar comprovante de
          identidade e outros documentos.
        </p>
        <h3>2. Dados Cadastrais</h3>
        <p>
          Você é responsável por fornecer informações corretas e atualizadas
          durante a abertura da conta. Mantenha seus dados em sigilo e não os
          compartilhe com terceiros.
        </p>
        <h3>3. Tarifas e Encargos</h3>
        <p>
          O FIAP OTEL Bank pode cobrar tarifas por determinados serviços. Os
          valores serão informados durante a abertura da conta e podem ser
          alterados. Cabe a você consultar e entender as tarifas aplicáveis.
        </p>
        <h3>4. Encerramento</h3>
        <p>
          O FIAP OTEL Bank pode encerrar ou suspender sua conta caso você
          descumpra estes termos ou pratique atividades fraudulentas ou ilegais.
          Você também pode solicitar o encerramento a qualquer momento, desde
          que não haja pendências.
        </p>
        <p>
          Ao abrir uma conta no FIAP OTEL Bank, você declara que leu, entendeu
          e concorda com estes Termos e Condições. Em caso de dúvidas, fale com
          nossa equipe de atendimento.
        </p>
      </Modal.Body>
    </>
  );
};

export default TermsAndConditionsModal;
