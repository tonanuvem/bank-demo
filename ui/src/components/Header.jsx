/**
 * Copyright (c) 2023 Cisco Systems, Inc. and its affiliates All rights reserved.
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file.
 */

import { Navbar, Nav, Container, NavDropdown } from "react-bootstrap";
import { toast } from "react-toastify";
import { LinkContainer } from "react-router-bootstrap";
import { useSelector, useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { useLogoutMutation } from "../slices/usersApiSlice";
import { logout } from "../slices/authSlice";
import "../index.css";

const CustomNavItems = ({ name, link }) => {
  return (
    <Nav.Item style={{ marginRight: 20 }}>
      <LinkContainer to={link}>
        <Nav.Link className="text-white">
          <span style={{ fontSize: "2vh" }}>{name}</span>
        </Nav.Link>
      </LinkContainer>
    </Nav.Item>
  );
};

const Header = () => {
  const { userInfo } = useSelector((state) => state.auth);

  const dispatch = useDispatch();
  const navigate = useNavigate();

  const [logoutApiCall] = useLogoutMutation();

  const logoutHandler = async () => {
    try {
      // const jwtCookie = Cookies.get("jwt");
      // if (!jwtCookie) {
      //   toast.error("Sessão não encontrada!");
      // } else {
      //   await logoutApiCall(jwtCookie).unwrap();
      //   dispatch(logout());
      //   toast.success("Sessão encerrada", {
      //     className: "toast-container-custom",
      //     autoClose: false,
      //     hideProgressBar: true,
      //     closeOnClick: true,
      //     pauseOnHover: true,
      //     draggable: true,
      //     progress: undefined,
      //     theme: "dark",
      //   });
      await logoutApiCall({email: userInfo.email}).unwrap();
      dispatch(logout());
      toast.success("Sessão encerrada", {
        className: "toast-container-custom",
        autoClose: 500,
        hideProgressBar: true,
        closeOnClick: true,
        pauseOnHover: true,
        draggable: true,
        progress: undefined,
        theme: "dark",
      });
      navigate("/login");
    } catch (err) {
      console.error(err);
    }
  };

  return (
    <header>
      <Navbar
        bg="dark"
        varient="dark"
        expand="lg"
        collapseOnSelect
        style={{ height: "10vh" }}
      >
        <Container>
          <LinkContainer to="/">
            <Navbar.Brand className="text-white text-uppercase">
              <img
                src="./src/assets/coin-front.png"
                // src="https://via.placeholder.com/45x45"
                alt="logo"
                width="70vw"
                height="auto"
              />
              <strong style={{ fontSize: "4vh" }}>FIAP OTEL </strong>
              <span
                style={{ fontSize: "4vh", fontWeight: "lighter", color: "red" }}
              >
                Bank
              </span>
            </Navbar.Brand>
          </LinkContainer>
          <Navbar.Toggle aria-controls="basic-navbar-nav" />
          <Navbar.Collapse id="basic-navbar-nav">
            <Nav className="ms-auto">
              {userInfo ? (
                <>
                  <NavDropdown
                    title="Contas"
                    id="accounts"
                    className="custom-nav-dropdown"
                    style={{ fontSize: "2vh", marginRight: 30 }}
                  >
                    <LinkContainer to="/">
                      <NavDropdown.Item>
                        <span style={{ fontSize: "1.5vh" }}>Minhas Contas</span>
                      </NavDropdown.Item>
                    </LinkContainer>
                    <LinkContainer to="/new-account">
                      <NavDropdown.Item>
                        <span style={{ fontSize: "1.5vh" }}>Nova Conta</span>
                      </NavDropdown.Item>
                    </LinkContainer>
                  </NavDropdown>
                  <CustomNavItems
                    style={{ marginRight: 30 }}
                    name="Transferir"
                    link="/transfer"
                  />
                  <CustomNavItems
                    style={{ marginRight: 30 }}
                    name="Extrato"
                    link="/transactions"
                  />
                  <CustomNavItems
                    style={{ marginRight: 30 }}
                    name="Empréstimos"
                    link="/loan"
                  />
                  <CustomNavItems
                    style={{ marginRight: 30 }}
                    name="Caixas Eletrônicos"
                    link="/find-atm"
                  />
                  <NavDropdown
                    title={userInfo.name}
                    id="username"
                    className="custom-nav-dropdown"
                    style={{ fontSize: "2vh" }}
                  >
                    <LinkContainer to="/profile">
                      <NavDropdown.Item>
                        <span style={{ fontSize: "1.5vh" }}>Dados Pessoais</span>
                      </NavDropdown.Item>
                    </LinkContainer>
                    <LinkContainer to="/login">
                      <NavDropdown.Item onClick={logoutHandler}>
                        <span style={{ fontSize: "1.5vh" }}>Sair</span>
                      </NavDropdown.Item>
                    </LinkContainer>
                  </NavDropdown>
                </>
              ) : (
                <>
                  <CustomNavItems
                    style={{ marginRight: 20 }}
                    name="Caixas Eletrônicos"
                    link="/find-atm"
                  />
                  <Nav.Item style={{ marginRight: 20 }}>
                    <LinkContainer to="/register">
                      <Nav.Link className="text-white">
                        <span style={{ fontSize: "2vh" }}>Cadastrar</span>
                      </Nav.Link>
                    </LinkContainer>
                  </Nav.Item>
                  <Nav.Item style={{ marginRight: 40 }}>
                    <LinkContainer to="/login">
                      <Nav.Link className="text-white">
                        <span style={{ fontSize: "2vh" }}>Entrar</span>
                      </Nav.Link>
                    </LinkContainer>
                  </Nav.Item>
                </>
              )}
            </Nav>
          </Navbar.Collapse>
        </Container>
      </Navbar>
    </header>
  );
};

export default Header;
