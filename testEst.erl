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


%% ESTRUCTURA MASTER 
%% LISTA QUE MANTIENE LA FUNCION MASTER [{nombre_cliente, nodo, pid}]

%% CHEQUEAR ESTO QUE NUNCA LO PROBAMOSS!!!!!

%% hacer mas descriptivo el error
%%masterClient([]) -> 
masterClient(ListClients, ListServers) ->
    register(mcx, self()),
    loopMasterClient(ListClients, ListServers).

loopMasterClient(ListClients, ListServers) ->
    receive {add, {Name, Node, Pid}} -> case (clientExists(Name, ListClients)) of
                                            true -> Pid ! {mc, errNameAlreadyExists};
                                            false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                     Pid ! {mc, addOk},
                                                     lists:map(fun(Srv) -> {mcx, Srv} ! {updateAdd, {Name, Node, Pid}} end, ListServers),
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
                                 end
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

%% [{Player1, Player2, Game, ListObs, LastMove}]

gameLookUp(Player1, Player2, []) -> error;
gameLookUp(Player1, Player2, [{P1, P2, G, LO, LM} | XS]) ->
    case (Player1 == P1 && Player2 == P2) of
        true -> {P1, P2, G, LO, LM};
        false -> gameLookUp(Player1, Player2, XS)
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
%% [{Player1, Player2, Game, ListObs, LastMove}]

%% ESTO DEBERIAMOS CAMBIARLO SEGURAMENTE, AGREGAR LOS IDGAMES, Y USAR LOCKS
loopMasterGames(ListGames, ListServers) ->
    receive {getListGames, PidPComando} -> PidPComando ! {listGames, ListGames};
            {addGame, PidPComando, P1} -> NewGame = {P1, "Libre", {0, 0}, [], "NA"},
%%                                          PidPComando ! {addGameOk, NewGame},
                                          case (lists:member(NewGame, ListGames)) of
                                              true -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateAdd, {NewGame, Node}} end, ListServers),
                                                      loopMasterGames(ListGames++[NewGame], ListServers);
                                              false -> loopMasterGames(ListGames, ListServers)
                                          end;            
            {removeGame, PidPComando, {P1, P2}} -> del = gameLookUp(P1, P2, ListGames),
                                                   if del /= error -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateDel, {{P1, P2}, Node}} end,ListServers),
                                                                      loopMasterGames(lists:delete(del, ListGames), ListServers)
                                                   end
                                                   PidPComando ! {removeGameOk, {P1, P2}};
            {updateGame, PidPComando, {P1, P2}, PacketGame} -> del = gameLookUp(P1, P2, ListGames),
                                                                                                                              

            {updateAdd, {Game, Node}} ->
            {updateDel, {{P1, P2}, Node}} ->
            

{move, IDGame, Player, NewGame} -> case gameLookUp(IDGame, ListGames) of
                                                   {ID, 










