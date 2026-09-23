/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { fetchBaseQuery, createApi } from "@reduxjs/toolkit/query/react";
import ApiUrls from "./apiUrls";

// VITE_USERS_URL ja' termina em "/" (".../api/users/"). As rotas abaixo NAO
// levam barra inicial, por isso -- "/auth" faria ".../api/users//auth".
// A barra dupla nao quebra a rota (o Express e' tolerante), mas o morgan
// grava o caminho exato como chegou: os logs de recusa de login ficavam
// "POST /api/users//auth 400", e nenhuma busca por "/api/users/auth" batia
// com isso -- MEDIDO em producao, com o painel de log mostrando "No data"
// apesar da recusa ter acontecido de verdade.
const usersUrl = import.meta.env.VITE_USERS_URL || ApiUrls.VITE_USERS_URL;

// const baseQuery = fetchBaseQuery({ baseUrl: 'http://host.docker.internal:8000/' });
const baseQuery = fetchBaseQuery({ 
  baseUrl: "",
});

export const apiSlice = createApi({
  baseQuery,
  tagTypes: ["User"],
  endpoints: () => ({}),
});

export const userApiSlice = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    login: builder.mutation({
      query: (data) => ({
        url: `${usersUrl}auth`,
        method: "POST",
        body: data,
        // credentials: 'include',
      }),
    }),
    logout: builder.mutation({
      query: (data) => ({
        url: `${usersUrl}logout`,
        method: "POST",
        body: data,
        headers: {
          'Content-Type': 'application/json',
        },
      }),
    }),
    register: builder.mutation({
      query: (data) => ({
        url: `${usersUrl}`,
        method: "POST",
        body: data,
      }),
    }),
    updateUser: builder.mutation({
      query: (data) => ({
        url: `${usersUrl}profile`,
        method: "PUT",
        body: data,
        // headers: {
        //   'Content-Type': 'application/json',
        //   'Authorization': data.token
        // },
      }),
    }),
  }),
});

export const {
  useLoginMutation,
  useLogoutMutation,
  useRegisterMutation,
  useUpdateUserMutation,
} = userApiSlice;
