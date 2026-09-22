/*
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

/*
 * Os enderecos vem do HOSTNAME QUE O NAVEGADOR USOU, e nao de um valor fixo.
 *
 * Por que isso importa: este arquivo e' compilado para dentro do bundle pelo
 * Vite. Com "localhost" fixo, quem abrisse a aplicacao pelo IP publico de uma
 * EC2 teria o proprio navegador chamando localhost:8000 -- ou seja, a maquina
 * DELE, onde nao ha nada escutando. O sintoma e' um erro de login que so'
 * aparece fora da maquina que hospeda a aplicacao, e nenhum log do servidor
 * registra nada, porque a requisicao nunca chega.
 *
 * Com window.location, a mesma imagem serve localhost, IP publico e qualquer
 * nome DNS, sem reconstruir nem reescrever arquivo.
 *
 * A PORTA do dashboard tambem nao e' fixa: ela chega em window.__FIAP_API__,
 * injetada no index.html quando o container sobe (mesmo mecanismo do agente
 * de RUM). Sem isso, quem publicasse o dashboard em outra porta -- o que
 * acontece quando a 5000 ja esta ocupada na maquina -- veria a UI chamando a
 * 5000 e recebendo erro de CORS de qualquer processo que estivesse la'.
 */

const HOST = window.location.hostname;
const PROTOCOL = window.location.protocol;
const PORTA_DASHBOARD =
  (typeof window !== "undefined" && window.__FIAP_API__?.dashboard) || 5000;

const VITE_USERS_URL = `${PROTOCOL}//${HOST}:8000/api/users/`;
const VITE_ATM_URL = `${PROTOCOL}//${HOST}:8001/api/atm/`;
const VITE_ACCOUNTS_URL = `${PROTOCOL}//${HOST}:${PORTA_DASHBOARD}/account/`;
const VITE_TRANSFER_URL = `${PROTOCOL}//${HOST}:${PORTA_DASHBOARD}/transaction/`;
const VITE_LOAN_URL = `${PROTOCOL}//${HOST}:${PORTA_DASHBOARD}/loan/`;

const ApiUrls = {
  VITE_USERS_URL,
  VITE_ATM_URL,
  VITE_ACCOUNTS_URL,
  VITE_TRANSFER_URL,
  VITE_LOAN_URL,
};

export default ApiUrls;
