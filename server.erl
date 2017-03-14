-module(server).
-compile(export_all).   
-import(testEst, [pbalance/1, connectNodes/1, masterClient/2, pstat/1, masterGames/2, getStateGames/3, getP2/1, gameLookUp/2, gameExists/2, listToString/1, obsExists/3, listToRow/1, getPlayerGames/2, getPlayerObsGames/2]).
-import(gameLogic, [makeMatrix/1, move/3, validMove/3, winGame/1]).

main(Args) ->
    dispatcher([list_to_integer(Args)]).

dispatcher([Port])->
    {ok,ListenSock} = gen_tcp:listen(Port,[{active,false}]),
    connectNodes(['srvA@jose-laptop','srvB@jose-laptop']),
    PidPstat = spawn(testEst, pstat, [['srvA@jose-laptop','srvB@jose-laptop']]),
    PidPbalance = spawn(testEst, pbalance, [[{'srvA@jose-laptop',0},{'srvB@jose-laptop',0}]]),
    io:format("Lanza MasterClient \n"),
    PidMasterClient = spawn(testEst, masterClient,[[],['srvA@jose-laptop','srvB@jose-laptop']]),
    PidMasterGames = spawn(testEst, masterGames, [[],['srvA@jose-laptop','srvB@jose-laptop']]), 
    io:format("Lanzo MasterGames \n"),
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames).


loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames)-> 
    {ok,Sock} = gen_tcp:accept(ListenSock),
    Pid = spawn(?MODULE,psocket,[Sock, PidPbalance, PidMasterClient, PidMasterGames]),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames).


psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames) ->
    receive ok -> ok end,
    ok = inet:setopts(Sock,[{active,true}]),
    receive
        {tcp, Socket, Msg} -> case string:str(string:strip(Msg),"CON") of
                                  1 -> PidMasterClient ! {add, {string:substr(string:strip(Msg),5), node(), self()}},
                                       receive 
                                           {mc, addOk} -> gen_tcp:send(Socket, ">> Conexion establecida correctamente :) << \n"),
                                                          looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames);
                                           {mc, errNameAlreadyExists} -> gen_tcp:send(Socket, "***Error: Nombre ya existe"),
                                                                         self() ! ok,
                                                                         psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames)
                                       end;
                                  N -> gen_tcp:send(Socket, "***Error: se esperaba el comando CON"),
                                       self() ! ok,
                                       psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames)
                              end
    end.
    

looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames) ->
    receive
           {tcp,Socket,Cmd} -> PidPbalance ! {req, self()},
                               receive 
                                   {ans, Node} -> io:format(Node),
                                                  spawn(Node, server, pcomando, [Cmd, node(), self(), PidMasterClient, PidMasterGames]),
                                                  looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames)
                               end;                            
           {pcomando, ok, Cmd, Msg} -> gen_tcp:send(Sock, Msg),
                                       looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames);
           {pcomando, error, Cmd, Msg} -> gen_tcp:send(Sock, Msg),
                                          looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames);
           {pcomando, salir, Msg} -> gen_tcp:send(Sock, Msg),
                                     gen_tcp:close(Sock)
    end.


pcomando(Cmd, Node, PidPSocket, PidMasterClient, PidMasterGames)->
    Tokens = string:tokens(Cmd, " "),
    case lists:nth(1, Tokens) of
         % LSG 
         "LSG" -> PidMasterGames ! {getListGames, self()},
                  receive {listGames, Respuesta} -> {Libres, Ocupados} = getStateGames(Respuesta, [], []),
                                                    PidPSocket ! {pcomando, ok, Cmd, ["Libres: ", listToString(Libres), " - Ocupados: ", listToString(Ocupados)]}
                  end;
         % NEW GameName 
         "NEW" -> GameName = lists:nth(2, Tokens),
                  {mcx, node()} ! {getPlayerName, PidPSocket, self()},
                  receive {playerName, Name} -> {mgx, node()} ! {addGame, self(), GameName, Name, node()},
                                                receive {mg, addOk} -> PidPSocket ! {pcomando, ok, Cmd, "Partida creada"};
                                                        {mg, errNameAlreadyExists} -> PidPSocket ! {pcomando, error, Cmd, "Nombre de juego ya existe, intente nuevamente"}
                                                end;
                          errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Jugador no registrado"}
                  end;
          %% ACC GameName
         "ACC" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> {Libres, Ocupados} = getStateGames(ListGames, [], []),
                                  case (lists:member(GameName, Libres)) of
                                      true -> {GN, P1, P2, G,LO, LM} = gameLookUp(GameName, ListGames),
                                              {mcx, node()} ! {getPlayerName, PidPSocket, self()},
                                              receive {playerName, PlayerName} -> case (P1 == PlayerName) of
                                                                                      true -> PidPSocket ! {pcomando, error, Cmd, "Accion invalida"};
                                                                                      false -> NewPacketGame = {GN, P1, PlayerName, G ,LO, PlayerName},
                                                                                               {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                               PidPSocket ! {pcomando, ok, Cmd, "Juego aceptado"},
                                                                                               timer:sleep(500),
                                                                                               {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient}
                                                                                  end
                                              end; 
                                      false -> PidPSocket ! {pcomando, error, Cmd, "Juego ocupado"}
                                  end
                      end
                  end;
         %% OBS GameName
         "OBS" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> PidMasterClient ! {getPlayerName, PidPSocket, self()},
                                  receive 
                                      errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Jugador no registrado"};
                                      {playerName, Name} -> case obsExists(Name, GameName, ListGames) of
                                                                true -> PidPSocket ! {pcomando, error, Cmd, "Ya esta observando"};
                                                                false -> PidMasterGames ! {addObs, self(), GameName, Name, node()},
                                                                         receive {addObsOk, GN} -> PidPSocket ! {pcomando, ok, Cmd, "Observacion iniciada"}
                                                                         end
                                                            end
                                  end
                      end
                  end;
         % LEA GameName
         "LEA" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> PidMasterClient ! {getPlayerName, PidPSocket, self()},
                                  receive 
                                      errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Jugador no registrado"};
                                      {playerName, Name} -> case obsExists(Name, GameName, ListGames) of
                                                                false -> PidPSocket ! {pcomando, error, Cmd, "Partida no observada"};
                                                                true -> PidMasterGames ! {delObs, self(), GameName, Name, node()},
                                                                        receive {removeObsOk, GN} -> PidPSocket ! {pcomando, ok, Cmd, "Observacion terminada"}
                                                                        end      
                                                            end
                                  end
                      end
                  end;
         % PLA
         "PLA" -> GameName = lists:nth(2, Tokens),
                  Jugada = lists:nth(3, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> {GN, P1, P2, G, LO, LM} = gameLookUp(GameName, ListGames),
                                  PidMasterClient ! {getPlayerName, PidPSocket, self()},
                                  receive 
                                      errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Operacion invalida"};
                                      {playerName, Name} -> case Name == LM of
                                                  true when (Jugada /= "0") -> PidPSocket ! {pcomando, error, Cmd, "Aguarde su turno"};
                                                  _ -> case list_to_integer(Jugada) of
                                                               0  -> case (Name == P1) of
                                                                          true -> NewPacketGame = {GN, P1, P2, G, LO, "-1"};
                                                                          false -> NewPacketGame = {GN, P1, P2, G, LO, "-2"}
                                                                     end,
                                                                     {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                     timer:sleep(500),
                                                                     {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient};

                                                               N when (Name == P1) -> case move(N, G, 1) of
                                                                                          error -> PidPSocket ! {pcomando, error, Cmd, "Jugada invalida"};

                                                                                          {empate, {T1,T2}} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, "00"},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient};

                                                                                          {T1, T2} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, Name},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient}
                                                                                      end;
                                                               N when (Name == P2) -> case move(N, G, 2) of
                                                                                          error -> PidPSocket ! {pcomando, error, Cmd, "Jugada invalida"};

                                                                                          {empate, {T1,T2}} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, "00"},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient};

                                                                                          {T1, T2} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, Name},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient}
                                                                                       end;
                                                               _ -> PidPSocket ! {pcomando, error, Cmd, "No es jugador de la partida ingresada"}
                                                           end
                                              end
                                  end
                      end
                  end;
         % UPD GameName                                    
         "UPD" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> {GN, P1, P2, {T1, T2}, LO, LM} = gameLookUp(GameName, ListGames),
                                  PidPSocket ! {pcomando, ok, Cmd, "Partida: "++GN++" || X: "++P1++" || O: "++P2++" || Ultimo en jugar: "++LM},
                                  timer:sleep(300),

                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix({T1, T2})), 1, 5)},
                                  timer:sleep(50),
                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix({T1, T2})), 7, 11)},
                                  timer:sleep(50),
                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix({T1, T2})), 13, 17)},
                                  timer:sleep(50),
                                  %PidPSocket ! {pcomando, ok, Cmd, listToRow(makeMatrix({T1, T2}))},

                                  case LM of
                                      "00" -> PidPSocket ! {pcomando, ok, Cmd, "**** Partida terminada - "++P1++" y "++P2++" han empatado"},
                                              timer:sleep(500),
                                              PidMasterGames ! {removeGame, self(), GameName, node()};
                                      "-1" -> PidPSocket ! {pcomando, ok, Cmd, "**** Partida terminada - "++P1++" ha abandonado - "++P2++" ha ganado"},
                                              timer:sleep(500),
                                              PidMasterGames ! {removeGame, self(), GameName, node()};
                                      "-2" -> PidPSocket ! {pcomando, ok, Cmd, "**** Partida terminada - "++P2++" ha abandonado - "++P1++" ha ganado"},
                                              timer:sleep(500),
                                              PidMasterGames ! {removeGame, self(), GameName, node()};
                                      P1 -> case winGame(T1) of
                                                false -> false;
                                                true -> PidPSocket ! {pcomando, ok, Cmd, "**** Partida terminada - "++P1++" ha ganado"},
                                                        timer:sleep(500),
                                                        PidMasterGames ! {removeGame, self(), GameName, node()}
                                            end;
                                      P2 -> case winGame(T2) of
                                                false -> false;
                                                true -> PidPSocket ! {pcomando, ok, Cmd, "**** Partida terminada - "++P2++" ha ganado"},
                                                        timer:sleep(500),
                                                        PidMasterGames ! {removeGame, self(), GameName, node()}
                                            end
                                  end

                      end
                  end;    
         "BYE" -> PidMasterClient ! {getPlayerName, PidPSocket, self()},
                  receive 
                      errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Operacion invalida"};
                      {playerName, Name} -> PidMasterGames ! {getListGames, self()},
                                            receive {listGames, ListGames} -> PlayedGames = getPlayerGames(Name, ListGames),
                                                                              ObsGames = getPlayerObsGames(Name, ListGames),
                                                                              lists:map(fun(X) -> PidMasterGames ! {delObs, self(), X, Name, node()} end, ObsGames),
                                                                              timer:sleep(1000),
                                                                              lists:map(fun(X) -> spawn(?MODULE, pcomando, ["PLA "++X++" 0", node(), PidPSocket, PidMasterClient, PidMasterGames]) end, PlayedGames),
                                                                              timer:sleep(1000),
                                                                              PidMasterClient ! {remove, {Name, node()}},
                                                                              PidPSocket ! {pcomando, salir, "-> Vuelva prontos!! :)"}
                                            end
                  end                   
    end.



