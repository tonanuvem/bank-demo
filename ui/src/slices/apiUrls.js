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
 * LIMITE CONHECIDO: as PORTAS continuam fixas. Se o dashboard for publicado
 * em outra porta que nao a 5000 (acontece quando a 5000 ja esta ocupada na
 * maquina), a UI continuara chamando a 5000.
 */

const HOST = window.location.hostname;
const PROTOCOL = window.location.protocol;

const VITE_USERS_URL = `${PROTOCOL}//${HOST}:8000/api/users/`;
const VITE_ATM_URL = `${PROTOCOL}//${HOST}:8001/api/atm/`;
const VITE_ACCOUNTS_URL = `${PROTOCOL}//${HOST}:5000/account/`;
const VITE_TRANSFER_URL = `${PROTOCOL}//${HOST}:5000/transaction/`;
const VITE_LOAN_URL = `${PROTOCOL}//${HOST}:5000/loan/`;

const ApiUrls = {
  VITE_USERS_URL,
  VITE_ATM_URL,
  VITE_ACCOUNTS_URL,
  VITE_TRANSFER_URL,
  VITE_LOAN_URL,
};

export default ApiUrls;
