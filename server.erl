-module(server).
-compile(export_all).   
-import(testEst, [pbalance/1, connectNodes/1, masterClient/2, pstat/1, masterGames/2, getStateGames/3, getP2/1, gameLookUp/2, gameExists/2, listToString/1, obsExists/3, listToRow/1, getPlayerGames/2, getPlayerObsGames/2]).
-import(gameLogic, [makeMatrix/1, move/3, validMove/3, winGame/1]).

%% spawneamos el pbalance en el servidor local, apenas empieza el dispatcher (va a haber uno por nodo)
dispatcher()->
    {ok,ListenSock} = gen_tcp:listen(8003,[{active,false}]),
    connectNodes(['srvA@jose-laptop','srvB@jose-laptop']),
    PidPstat = spawn(testEst, pstat, [['srvA@jose-laptop','srvB@jose-laptop']]),
    PidPbalance = spawn(testEst, pbalance, [[{'srvA@jose-laptop',0},{'srvB@jose-laptop',0}]]),
    io:format("Lanza MasterClient \n"),
    PidMasterClient = spawn(testEst, masterClient,[[],['srvA@jose-laptop','srvB@jose-laptop']]),
    PidMasterGames = spawn(testEst, masterGames, [[],['srvA@jose-laptop','srvB@jose-laptop']]), 
    io:format("Lanzo MasterGames \n"),
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames).


loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames)-> %% Mantiene todos los clientes conectados a este server ClientList
    {ok,Sock} = gen_tcp:accept(ListenSock),
    io:format("Acepto conexion\n"),
    Pid = spawn(?MODULE,psocket,[Sock, PidPbalance, PidMasterClient, PidMasterGames]),
    io:format("Hizo spawn del psocket\n"),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient, PidMasterGames).

%% Avisar masterClient que hay un nuevo cliente, mandar {add, {nombreCliente, node(), self()}}
%% Hay que pensar el modo de resolver si falla, y el nombre ya esta usado, habria que esperar una respuesta.
%% HACER RECEIVE DEL COMANDO CON hernan, y habria que tomar ese nombre para preguntarle al masterClient
psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames) ->
    io:format("Entre a psocket\n"),
    receive ok -> ok end,
    io:format("pase el ok\n"),
    ok = inet:setopts(Sock,[{active,true}]),
    receive
        {tcp, Socket, Msg} -> case string:str(string:strip(Msg),"CON") of
                                  1 -> PidMasterClient ! {add, {string:substr(string:strip(Msg),5), node(), self()}},
                                       io:format("Mando nombre a masterclient\n"),
                                       receive 
                                           {mc, addOk} -> gen_tcp:send(Socket, ">> Conexion establecida correctamente :) << \n"),
                                                          looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames);
                                           {mc, errNameAlreadyExists} -> gen_tcp:send(Socket, "***Error: Nombre ya existe"),
                                                                         self() ! ok,
                                                                         psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames)
                                       end;
                                  N -> gen_tcp:send(Socket, "***Error: se esperaba el comando CON"),
                                       io:format("Entro guarda 1 psocket\n"),
                                       self() ! ok,
                                       psocket(Sock, PidPbalance, PidMasterClient, PidMasterGames)
                              end
    end.
    
%%    PidMasterClient ! {add, {
%%    io:format("paso psocket\n"),
%%    string:substr(string:strip(Msg),5)

%%ver lo del mensajito de respuesta de pbalance!!
%% PARA QUE PLAYER NAME??
looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames) ->
%%    ok = inet:setopts(Sock,[{active,true}]),
    io:format("entro a looppsocket\n"),
    receive
           {tcp,Socket,Cmd} -> PidPbalance ! {req, self()},
                               io:format("mando peticion a pbalance\n"),
                               receive 
                                   {ans, Node} -> io:format(Node),
                                                  spawn(Node, server, pcomando, [Cmd, node(), self(), PidMasterClient, PidMasterGames])
                               end;                            
           {pcomando, ok, Cmd, Msg} -> io:format("Se recibio el mensaje\n"),
                                       gen_tcp:send(Sock, Msg);
           {pcomando, error, Cmd, Msg} -> io:format("Se recibio el mensaje\n"),
                                          gen_tcp:send(Sock, Msg)
    end,
    looppsocket(Sock, PidPbalance, PidMasterClient, PidMasterGames).

% PARA QUE PLAYER NAME??
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
                  io:format("mande mensaje a masterclient\n"),
                  receive {playerName, Name} -> io:format("Antes de mandar addGame\n"),
                                                {mgx, node()} ! {addGame, self(), GameName, Name, node()},
                                                io:format("Antes del receive de mgx\n"),
                                                receive {mg, addOk} -> io:format("Se envio el mensaje\n"),
                                                                       PidPSocket ! {pcomando, ok, Cmd, "Partida creada"};
                                                        {mg, errNameAlreadyExists} -> PidPSocket ! {pcomando, error, Cmd, "Nombre de juego ya existe, intente nuevamente"}
                                                end;
                          errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Jugador no registrado"}
                  end;
          %% ACC GameName
         "ACC" -> GameName = lists:nth(2, Tokens),
%                  io:format("Antes de mandar el mensaje a MG\n"),
                  PidMasterGames ! {getListGames, self()},
%                  io:format("Despues de mandar el mensaje a MG\n"),
                  receive {listGames, ListGames} ->
%                      io:format("Respondio MG\n"), 
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
                      end %% ENVIAR TABLERO A AMBOS JUGADORES, Y A LOS OBSERVADORES
                  end;
         %% OBS GameName {addObs, PidPComando, GameName, PlayerName, Node} {getPlayerName, PidPSocket, PidPComando}
         "OBS" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
%                  io:format("Despues de mandar el mensaje a MG\n"),
                  receive {listGames, ListGames} ->
%                      io:format("Respondio MG\n"), 
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
         % PLA GameName jugada   {getPlayerName, PidPSocket, PidPComando}
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
                                                                                          {T1, T2} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, Name},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                     % PidPSocket ! {pcomando, ok, Cmd, "ESTADOPLA1: "++integer_to_list(length(Name))++" "++integer_to_list(length(P1))},
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient}
                                                                                      end;
                                                               N when (Name == P2) -> case move(N, G, 2) of
                                                                                          error -> PidPSocket ! {pcomando, error, Cmd, "Jugada invalida"};
                                                                                          {T1, T2} -> NewPacketGame = {GN, P1, P2, {T1, T2}, LO, Name},
                                                                                                      {mgx, node()} ! {gameChange, self(), GameName, NewPacketGame, node()},
                                                                                                      timer:sleep(500),
                                                                                                     % PidPSocket ! {pcomando, ok, Cmd, "ESTADOPLA1: "++lists:flatten(io_lib:format("~p",[Name]))++"||"++lists:flatten(io_lib:format("~p",[P1]))},
                                                                                                      {mgx, node()} ! {sendUpdatesUPD, GameName, PidMasterClient}
                                                                                       end
                                                           end
                                              end
                                  end
                      end
                  end;
         % UPD GameName     {removeGame, PidPComando, GameName, Node}                                       
         "UPD" -> GameName = lists:nth(2, Tokens),
                  PidMasterGames ! {getListGames, self()},
                  receive {listGames, ListGames} ->
                      case gameExists(GameName, ListGames) of 
                          false -> PidPSocket ! {pcomando, error, Cmd, "Juego inexistente"};
                          true -> {GN, P1, P2, {T1, T2}, LO, LM} = gameLookUp(GameName, ListGames),
                                  PidPSocket ! {pcomando, ok, Cmd, "Partida: "++GN++" || X: "++P1++" || O: "++P2++" || Ultimo en jugar: "++LM},
                                  timer:sleep(500),
                                  PidPSocket ! {pcomando, ok, Cmd, listToRow(makeMatrix({T1, T2}))},
%                                  PidPSocket ! {pcomando, ok, Cmd, "ESTADOUPD: "++integer_to_list(T1)++" "++integer_to_list(T2)},
                                  case LM of
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
%                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix(G)), 1, 5)},
%                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix(G)), 7, 11)},
%                                  PidPSocket ! {pcomando, ok, Cmd, string:sub_string(listToRow(makeMatrix(G)), 13, 17)}  
                      end
                  end;    
         "BYE" -> PidMasterClient ! {getPlayerName, PidPSocket, self()},
                  receive 
                      errPidPlayerNotExists -> PidPSocket ! {pcomando, error, Cmd, "Operacion invalida"};
                      {playerName, Name} -> PidMasterGames ! {getListGames, self()},
                                            receive {listGames, ListGames} -> PlayedGames = getPlayerGames(Name, ListGames),
                                                                              ObsGames = getPlayerObsGames(Name, ListGames),
                                                                              lists:map(fun(X) -> spawn(node(), server, pcomando, ["PLA "++X++" 0", node(), PidPSocket, PidMasterClient, PidMasterGames]) end, PlayedGames),
                                                                              lists:map(fun(X) -> PidMasterGames ! {delObs, self(), X, Name, node()} end, ObsGames),
                                                                              PidMasterClient ! {remove, {Name, node()}},
                                                                              PidPSocket ! {pcomando, ok, Cmd, "Vuelva pronto :)"}
                                            end
                  end                   
    end.                            
%         "PLA" -> %% ENVIAR TABLERO A AMBOS JUGADORES, Y A LOS OBSERVADORES
         %% Si se va P2, pasar a que sea P1
%         "BYE" ->

%% deberia computar el Cmd, y devolverle una respuesta a psocket
% NO SE POR QUE, PERO FUNCIONA ASI, PREGUNTAR A GUILLERMO. POR QUE NO ANDA SI AGREGAMOS EL NODO???




