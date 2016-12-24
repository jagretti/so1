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
                                            true -> Pid ! {mc, errNameAlreadyExists},
                                                    io:format("El nombre ya existe \n"),
                                                    loopMasterClient(ListClients, ListServers);
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
    {getListGames, PidPComando} -> PidPComando ! {listGames, ListGames};
    {addGame, PidPComando, GameName, P1, Node} -> NewGame = {GameName, P1, "Libre", {0, 0}, [], "NA"},
                                            case (gameExists(GameName, ListGames)) of
                                                false -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateAdd, {NewGame, Node}} end, ListServers),
                                                         PidPComando ! {mg, addOk},
                                                         loopMasterGames(ListGames++[NewGame], ListServers);
                                                true -> PidPComando ! {mg, errNameAlreadyExists},
                                                        loopMasterGames(ListGames, ListServers)
                                            end;            
    {removeGame, PidPComando, GameName, Node} -> del = gameLookUp(GameName, ListGames),
                                           if del /= error -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateDel, {GameName, Node}}end,ListServers),
                                                              PidPComando ! {removeGameOk, GameName},
                                                              loopMasterGames(lists:delete(del, ListGames), ListServers)
                                           end;                                           
    {gameChange, PidPComando, GameName, NewPacketGame, Node} -> lists:delete(gameLookUp(GameName, ListGames), ListGames),
                                                          lists:map(fun(Srv) -> {mgx, Srv} ! {updateGame, {GameName, NewPacketGame, Node}} end, ListServers),
                                                          loopMasterGames(ListGames++[NewPacketGame], ListServers);
    {updateGame, {GameName, NewPacketGame, Node}} -> case (Node == node()) of
                                                         true -> loopMasterGames(ListGames, ListServers);
                                                         false -> PacketGame = gameLookUp(GameName, ListGames),
                                                                  NewListGames = lists:delete(PacketGame, ListGames),
                                                                  loopMasterGames(NewListGames++[NewPacketGame], ListServers)
                                                     end    
    end.
% PROBAR ESTO QUE NO LO PROBAMOS                                                                                                                      

% HACER!!
%{updateAddObs
%{updateDelObs
%{addObs
%{delObs


%{move, IDGame, Player, NewGame} -> case gameLookUp(IDGame, ListGames) of
%                                                   {ID, 










