-module(testEst).
-compile(export_all).


% Sección de estadísticas
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


% Función de administración de clientes

masterClient(ListClients, ListServers) ->
    register(mcx, self()),
    loopMasterClient(ListClients, ListServers).

loopMasterClient(ListClients, ListServers) ->
    receive {add, {Name, Node, Pid}} -> case (clientExists(Name, ListClients)) of
                                            true -> Pid ! {mc, errNameAlreadyExists},
                                                    loopMasterClient(ListClients, ListServers);
                                            false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                     Pid ! {mc, addOk},
                                                     lists:map(fun(Srv) -> {mcx, Srv} ! {updateAdd, {Name, Node, Pid}} end, ListServers),
                                                     loopMasterClient(NewListClients, ListServers)
                                        end;
            {remove, {Name, Node}} -> Del = clientLookUp(Name, ListClients),
                                      lists:map(fun(Srv) -> {mcx, Srv} ! {updateDel, {Name, Node}} end,ListServers),
                                      loopMasterClient(lists:delete(Del, ListClients), ListServers);
                              
            {updateAdd, {Name, Node, Pid}} -> case (Node == node()) of
                                                  true -> loopMasterClient(ListClients, ListServers);
                                                  false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                           loopMasterClient(NewListClients, ListServers)
                                              end;
            {updateDel, {Name, Node}} -> Del = clientLookUp(Name, ListClients),
                                         loopMasterClient(lists:delete(Del, ListClients), ListServers);

                                         
            {getPlayerName, PidPSocket, PidPComando} -> case (clientNameLookUp(PidPSocket, ListClients)) of
                                                            error -> PidPComando ! errPidPlayerNotExists,
                                                                     loopMasterClient(ListClients, ListServers);
                                                            Name -> PidPComando ! {playerName, Name},
                                                                    loopMasterClient(ListClients, ListServers)
                                                        end;
            {getPidsPSockets, P1, P2, LO, PidAns} -> {Na1, No1, Pid1} = clientLookUp(P1, ListClients),
                                                     case clientLookUp(P2, ListClients) of
                                                         {Na2, No2, Pid2} -> PidObservers = lists:map(fun(X) -> clientLookUp(X, ListClients) end, LO), 
                                                                             PidObservers1 = lists:map(fun({N, No, P}) -> {No, P} end, PidObservers),
                                                                             PidAns ! {playerPids, [{No1, Pid1}] ++ [{No2, Pid2}] ++ PidObservers1},
                                                                             loopMasterClient(ListClients, ListServers);
                                                         error -> PidObservers = lists:map(fun(X) -> clientLookUp(X, ListClients) end, LO), 
                                                                  PidObservers1 = lists:map(fun({N, No, P}) -> {No, P} end, PidObservers),
                                                                  PidAns ! {playerPids, [{No1, Pid1}] ++ PidObservers1},
                                                                  loopMasterClient(ListClients, ListServers)
                                                     end
    end.


% Función de administración de juegos

masterGames(ListGames, ListServers) -> 
    register(mgx, self()),
    loopMasterGames(ListGames, ListServers).


loopMasterGames(ListGames, ListServers) ->
    receive 
    {updateAdd, {PacketGame, Node}} -> case (Node == node()) of
                                           true -> loopMasterGames(ListGames, ListServers);
                                           false -> NewListGames = ListGames++[PacketGame],
                                                    loopMasterGames(NewListGames, ListServers)
                                       end;
    {updateDel, {GameName, Node}} -> Del = gameLookUp(GameName, ListGames),
                                     loopMasterGames(lists:delete(Del, ListGames), ListServers);
                                                          
    {getListGames, PidPComando} -> PidPComando ! {listGames, ListGames},
                                   loopMasterGames(ListGames, ListServers); 
    {addGame, PidPComando, GameName, P1, Node} -> NewGame = {GameName, P1, libre, {0, 0}, [], "NA"},
                                            case (gameExists(GameName, ListGames)) of
                                                false -> lists:map(fun(Srv) -> {mgx, Srv} ! {updateAdd, {NewGame, Node}} end, ListServers),
                                                         PidPComando ! {mg, addOk},
                                                         loopMasterGames(ListGames++[NewGame], ListServers);
                                                true -> PidPComando ! {mg, errNameAlreadyExists},
                                                        loopMasterGames(ListGames, ListServers)
                                            end;            
    {removeGame, PidPComando, GameName, Node} -> Del = gameLookUp(GameName, ListGames),
                                                 lists:map(fun(Srv) -> {mgx, Srv} ! {updateDel, {GameName, Node}}end,ListServers),
                                                 PidPComando ! {removeGameOk, GameName},
                                                 loopMasterGames(ListGames, ListServers);
                                          
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


% Funciones auxiliares
                              
listToString([]) -> "";
listToString([X]) -> X;
listToString([X | XS]) -> string:concat(string:concat(X, ", "), listToString(XS)).

listToRow([]) -> "";
listToRow([X]) -> X;
listToRow([X | XS]) -> string:concat(string:concat(X, " "), listToRow(XS)).

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
    if P2 == libre -> getStateGames(XS, Libres ++ [GN], Ocupados);
       P2 /= libre -> getStateGames(XS, Libres, Ocupados ++ [GN])
    end.  
    
getP2({GN, P1, P2, LO, LM}) -> P2.

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

getPlayerGames(PlayerName, []) -> [];
getPlayerGames(PlayerName, [{GN, P1, P2, G, LO, LM} | XS]) ->
    case ((PlayerName == P1) or (PlayerName == P2)) of
        true -> [GN]++getPlayerGames(PlayerName, XS);
        false -> getPlayerGames(PlayerName, XS)
    end.

getPlayerObsGames(PlayerName, []) -> [];
getPlayerObsGames(PlayerName, [{GN, P1, P2, G, LO, LM} | XS]) ->
    case lists:member(PlayerName, LO) of
        true -> [GN]++getPlayerObsGames(PlayerName, XS);
        false -> getPlayerObsGames(PlayerName, XS)
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






