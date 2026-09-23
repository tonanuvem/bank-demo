/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import asyncHandler from "express-async-handler";
import ATM from "../models/atmModel.js";

// @desc    Returns list of all ATMs
// @route   POST /api/atm
// @access  Public
const getATMs = asyncHandler(async (req, res) => {
  let query = {
    interPlanetary: false,
  };
  if (req.body.isOpenNow) {
    query.isOpen = true;
  }
  if (req.body.isInterPlanetary) {
    query.interPlanetary = true;
  }
  const ATMs = await ATM.find(query, {
    name: 1,
    coordinates: 1,
    address: 1,
    isOpen: 1,
  });
  const shuffledATMs = [...ATMs].sort(() => Math.random() - 0.5).slice(0, 4);
  // `if (shuffledATMs)` era codigo morto: array vazio e' truthy em JavaScript,
  // entao o 404 NUNCA disparava e "nenhum caixa encontrado" saia como 200 com
  // lista vazia. Com os dados atuais nenhuma combinacao de filtro chega a
  // zero, mas o ramo agora existe de verdade.
  if (shuffledATMs.length) {
    res.status(200).json(shuffledATMs);
  } else {
    console.warn("No ATMs found: nenhum caixa para o filtro pedido");
    res.status(404).json("No ATMs found");
  }
});

// @desc    Add new ATM
// @route   POST /atm/add
// @access  Private
const addATM = asyncHandler(async (req, res) => {
  const {
    name,
    street,
    city,
    state,
    zip,
    latitude,
    longitude,
    monFri,
    satSun,
    holidays,
    atmHours,
    numberOfATMs,
    isOpen,
    interPlanetary,
  } = req.body;
  const atm = new ATM({
    name,
    address: {
      street,
      city,
      state,
      zip,
    },
    coordinates: {
      latitude,
      longitude,
    },
    timings: {
      monFri,
      satSun,
      holidays,
    },
    atmHours,
    numberOfATMs,
    isOpen,
    interPlanetary,
  });

  const createdATM = await atm.save();
  if (createdATM) {
    res.status(201).json(createdATM);
  } else {
    res.status(404);
    throw new Error("Could not create ATM");
  }
});

// @desc    Add specific ATM data
// @route   GET /atm/:id
// @access  Public
const getSpecificATM = asyncHandler(async (req, res) => {
  const atm = await ATM.findById(req.params.id);
  if (atm) {
    res.status(200).json({
      coordinates: atm.coordinates,
      timings: atm.timings,
      atmHours: atm.atmHours,
      numberOfATMs: atm.numberOfATMs,
      isOpen: atm.isOpen,
    });
  } else {
    // O UNICO caso deste lab em que a falha de negocio tambem e' visivel no
    // indicador tecnico: o cliente abre um caixa que nao existe mais e recebe
    // 404. Serve de contraexemplo -- "falha de negocio e' invisivel" nao e'
    // lei, e' consequencia de como cada rota foi desenhada.
    console.warn(`ATM not found: id ${req.params.id}`);
    res.status(404).json({ message: "ATM information not found" });
  }
});

export { getATMs, addATM, getSpecificATM };
