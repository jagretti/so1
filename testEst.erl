-module(testEst).
-compile(export_all).

-define(times, 10000).

%%srvInitTable = [{'srvA@jose-laptop',0}, {'srvB@jose-laptop',0}]

%% Estructura de Lista de Juegos, administrada por masterGames
%% [{IdGame, Player1, Player2, Game, ListObs, LastMove}]
%%
%%
%%
%%
%%
%%
%%
%%

connectNodes(ListServers) ->
    lists:map(fun(Name) -> net_kernel:connect_node(Name) end, ListServers).

pstat(ListServers) ->
    register(pstatx, self()),
    loopPstat(ListServers).

loopPstat(ListServers) ->
    receive after 5000 -> {A, St} = erlang:statistics(reductions), 
                          lists:map(fun(Srv) -> {pbalancex, Srv} ! {load, node(), self(), St} end, ListServers)
    end,
    loopPstat(ListServers).

listToString([]) -> "";
listToString([X]) -> X;
listToString([X | XS]) -> string:concat(string:concat(X, ", "), listToString(XS)).



%% ESTRUCTURA MASTER 
%% LISTA QUE MANTIENE LA FUNCION MASTER [{nombre_cliente, nodo, pid}]

%% CHEQUEAR ESTO QUE NUNCA LO PROBAMOSS!!!!!

%% hacer mas descriptivo el error
%%masterClient([]) -> 
masterClient(ListClients, ListServers) ->
    register(mcx, self()),
    loopMasterClient(ListClients, ListServers).

loopMasterClient(ListClients, ListServers) ->
    io:format("Entro a loopMasterClient\n"),
    receive {add, {Name, Node, Pid}} -> case (clientExists(Name, ListClients)) of
                                            true -> Pid ! {mc, errNameAlreadyExists},
                                                    io:format("El nombre ya existe \n"),
                                                    loopMasterClient(ListClients, ListServers);
                                            false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                     Pid ! {mc, addOk},
                                                     lists:map(fun(Srv) -> {mcx, Srv} ! {updateAdd, {Name, Node, Pid}} end, ListServers),
                                                     io:format("llegue hasta aca\n"),
                                                     loopMasterClient(NewListClients, ListServers)
                                        end;
            {remove, {Name, Node}} -> del = clientLookUp(Name, ListClients),
                                      if del /= error -> lists:map(fun(Srv) -> {mcx, Srv} ! {updateDel, {Name, Node}} end,ListServers),
                                                         loopMasterClient(lists:delete(del, ListClients), ListServers)
                              end;
            {updateAdd, {Name, Node, Pid}} -> case (Node == node()) of
                                                  true -> loopMasterClient(ListClients, ListServers);
                                                  false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                           loopMasterClient(NewListClients, ListServers)
                                              end;
            {updateDel, {Name, Node}} -> case (Node == node()) of
                                     true -> loopMasterClient(ListClients, ListServers);
                                     false -> loopMasterClient(lists:delete(del, ListClients), ListServers)
                                 end;
            {getPlayerName, PidPSocket, PidPComando} -> io:format("Entro en getPlayerName\n"),
                                                        case (clientNameLookUp(PidPSocket, ListClients)) of
                                                            error -> io:format("Antes de mandar a pcomando error\n"),
                                                                     PidPComando ! errPidPlayerNotExists,
                                                                     io:format("Mando error a pcomando\n"),
                                                                     loopMasterClient(ListClients, ListServers);
                                                            Name -> io:format("Antes de mandar a pcomando Ok\n"),
                                                                    PidPComando ! {playerName, Name},
                                                                    io:format("Manda el nombre a pcomando\n"),
                                                                    loopMasterClient(ListClients, ListServers)
                                                        end;
            {getPidsPSockets, P1, P2, LO, PidAns} -> {Na1, No1, Pid1} = clientLookUp(P1, ListClients),
                                                     {Na2, No2, Pid2} = clientLookUp(P2, ListClients),
                                                     PidObservers = lists:map(fun(X) -> clientLookUp(X, ListClients) end, LO), 
                                                     PidObservers1 = lists:map(fun({N, No, P}) -> {No, P} end, PidObservers),
                                                     PidAns ! {playerPids, [{No1, Pid1}] ++ [{No2, Pid2}] ++ PidObservers1},
                                                     loopMasterClient(ListClients, ListServers) 
    end.
                              
%% chequear que ande cuando se da de baja un jugador, que se pueda reutilizar el nombre. (esto lo deberia hacer pcomando).
%%FUNC AUXILIARES
clientExists(Name, []) -> false;
clientExists(Name, [{Na, _, _} | XS]) -> 
    if Name == Na -> true;
       Name /= Na -> clientExists(Name, XS)
    end.

clientLookUp(Name, []) -> error;
clientLookUp(Name, [{Na, No, P} | XS]) -> 
    if Name == Na -> {Na, No, P};
       Name /= Na -> clientLookUp(Name, XS)
    end.

clientNameLookUp(Pid, []) -> error;
clientNameLookUp(Pid, [{Na, No, P} | XS]) -> 
    if Pid == P -> Na;
       Pid /= P -> clientNameLookUp(Pid, XS)
    end.

getStateGames([], Libres, Ocupados) -> {Libres, Ocupados};
getStateGames([{GN, P1, P2, G, LO, LM} | XS], Libres, Ocupados) ->
    if P2 == "Libre" -> getStateGames(XS, Libres ++ [GN], Ocupados);
       P2 /= "Libre" -> getStateGames(XS, Libres, Ocupados ++ [GN])
    end.  
    
getP2({GN, P1, P2, LO, LM}) -> P2.


%% [{GameName, Player1, Player2, Game, ListObs, LastMove}]

gameExists(GameName, []) -> false;
gameExists(GameName, [{GN, P1, P2, G, LO, LM} | XS]) ->
    case (GameName == GN) of
        true -> true;
        false -> gameExists(GameName, XS)
    end.

gameLookUp(GameName, []) -> error;
gameLookUp(GameName, [{GN, P1, P2, G, LO, LM} | XS]) ->
    case (GameName == GN) of
        true -> {GN, P1, P2, G, LO, LM};
        false -> gameLookUp(GameName, XS)
    end.

getSrvLoad([{X, L} | XS], SrvName) ->
    if 
        X == SrvName -> L;
        X /= SrvName -> getSrvLoad(XS, SrvName)
    end.


getSrvMinLoad([{X, L} | XS]) -> getSrvMinAux(XS, {X, L}).

getSrvMinAux([], {SrvName, _}) -> SrvName;
getSrvMinAux([{X, L} | XS], {SrvName, Load}) -> 
    if L < Load -> getSrvMinAux(XS, {X, L});
       L >= Load -> getSrvMinAux(XS, {SrvName, Load})
    end.
                        
obsExists(PlayerName, GameName, []) -> error;
obsExists(PlayerName, GameName, [{GN, P1, P2, G, LO, LM} | XS]) ->
    case (GameName == GN) of
        true -> case lists:member(PlayerName, LO) of
                    true -> true;
                    false -> false
                end;
        false -> obsExists(PlayerName, GameName, XS)
    end.

%%self no haria falta
pbalance(SrvTable) ->
    register(pbalancex, self()),
    looppbalance(SrvTable).

looppbalance(SrvTable) ->
    receive 
        {load, NameSrv, PidSrv, St} -> NewSrvTable = lists:delete({NameSrv, getSrvLoad(SrvTable, NameSrv)}, SrvTable)++[{NameSrv, St}],
                                       looppbalance(NewSrvTable);
        {req, Pid} -> Pid ! {ans, getSrvMinLoad(SrvTable)},
                      looppbalance(SrvTable)
    end.

masterGames(ListGames, ListServers) -> 
    register(mgx, self()),
    loopMasterGames(ListGames, ListServers).

%%lists:map(fun(Srv) -> {mcx, Srv} ! {updateAdd, {Name, Node, Pid}} end, ListServers),
%% [{GameName, Player1, Player2, Game, ListObs, LastMove}]

%% La parte de mensajes mg la deberian implementar los pcomando! 
%%  EN LINEAS 150, 157, 162 la variable Node esta siendo usada sin que exista, ver como hacer (la agrego a donde llegan los msjs)
loopMasterGames(ListGames, ListServers) ->
    io:format("Entro a loopMasterGames\n"),
    receive 
    {updateAdd, {PacketGame, Node}} -> case (Node == node()) of
                                           true -> loopMasterGames(ListGames, ListServers);
                                           false -> NewListGames = ListGames++[PacketGame],
                                                    loopMasterGames(NewListGames, ListServers)
                                       end;
    {updateDel, {GameName, Node}} -> case (Node == node()) of
                                         true -> loopMasterGames(ListGames, ListServers);
                                         false -> del = gameLookUp(GameName, ListGames),
                                                  loopMasterGames(lists:delete(del, ListGames), ListServers)
                                     end;                                                          
    {getListGames, PidPComando} -> PidPComando ! {listGames, ListGames},
                                   loopMasterGames(ListGames, ListServers); 
    {addGame, PidPComando, GameName, P1, Node} -> NewGame = {GameName, P1, "Libre", {0, 0}, [], "NA"},
                                            case (gameExists(GameName, ListGames)) of
                                                false -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateAdd, {NewGame, Node}} end, ListServers),
                                                         PidPComando ! {mg, addOk},
                                                         loopMasterGames(ListGames++[NewGame], ListServers);
                                                true -> PidPComando ! {mg, errNameAlreadyExists},
                                                        loopMasterGames(ListGames, ListServers)
                                            end;            
    {removeGame, PidPComando, GameName, Node} -> del = gameLookUp(GameName, ListGames),
                                                 case (del == error) of
                                                     false -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateDel, {GameName, Node}}end,ListServers),
                                                              PidPComando ! {removeGameOk, GameName},
                                                              loopMasterGames(lists:delete(del, ListGames), ListServers);
                                                     true -> PidPComando ! {mg, errGameNotExists},
                                                             loopMasterGames(ListGames, ListServers)
                                           end;                                           
    {gameChange, PidPComando, GameName, NewPacketGame, Node} -> NewListGames = lists:delete(gameLookUp(GameName, ListGames), ListGames),      
                                                                lists:map(fun(Srv) -> {mgx, Srv} ! {updateGame, {GameName, NewPacketGame, Node}} end, ListServers),
                                                                loopMasterGames(NewListGames++[NewPacketGame], ListServers);
    {updateGame, {GameName, NewPacketGame, Node}} -> case (Node == node()) of
                                                         true -> loopMasterGames(ListGames, ListServers);
                                                         false -> PacketGame = gameLookUp(GameName, ListGames),
                                                                  NewListGames = lists:delete(PacketGame, ListGames),
                                                                  loopMasterGames(NewListGames++[NewPacketGame], ListServers)
                                                     end;
    {addObs, PidPComando, GameName, PlayerName, Node} -> {GN, P1, P2, Game, LO, LM} = gameLookUp(GameName, ListGames),
                                                         NewPacketGame = {GN, P1, P2, Game, LO++[PlayerName], LM},
                                                         NewListGames = lists:delete({GN, P1, P2, Game, LO, LM}, ListGames),
                                                         lists:map(fun(Srv) -> {mgx, Srv} ! {updateGame, {GameName, NewPacketGame, Node}} end, ListServers),
                                                         PidPComando ! {addObsOk, GameName},          
                                                         loopMasterGames(NewListGames++[NewPacketGame], ListServers);
    {delObs, PidPComando, GameName, PlayerName, Node} -> {GN, P1, P2, Game, LO, LM} = gameLookUp(GameName, ListGames),
                                                         NewPacketGame = {GN, P1, P2, Game, lists:delete(PlayerName, LO), LM},
                                                         NewListGames = lists:delete({GN, P1, P2, Game, LO, LM}, ListGames),
                                                         lists:map(fun(Srv) -> {mgx, Srv} ! {updateGame, {GameName, NewPacketGame, Node}} end, ListServers),
                                                         PidPComando ! {removeObsOk, GameName},
                                                         loopMasterGames(NewListGames++[NewPacketGame], ListServers);
    {sendUpdatesUPD, GameName, PidMasterClient} -> {GN, P1, P2, Game, LO, LM} = gameLookUp(GameName, ListGames),
                                                   {mcx, node()} ! {getPidsPSockets, P1, P2, LO, self()},
                                                   receive 
                                                       {playerPids, ListPlayers} -> lists:map(fun({No, Pid}) -> spawn(No, server, pcomando, ["UPD "++GameName, No, Pid, PidMasterClient, self()]) end, ListPlayers)
                                                   end,
                                                   loopMasterGames(ListGames, ListServers)
    end.




% PROBAR ESTO QUE NO LO PROBAMOS                                                                                                                      

%% Toda los mensajes que comienzan con update son solo mensajes entre servidores, los demas entre pcomandos y servidores.

% HACER!!
%{updateAddObs
%{updateDelObs
%{addObs
%{delObs


%{move, IDGame, Player, NewGame} -> case gameLookUp(IDGame, ListGames) of
%                                                   {ID, 










