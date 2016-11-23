-module(testEst).
-compile(export_all).

-define(times, 10000).

%%srvInitTable = [{'srvA@jose-laptop',0}, {'srvB@jose-laptop',0}]

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
masterClient(ListClients) ->
    receive {add, {Name, Node, Pid}} -> case (clientExists(Name, ListClients)) of
                                            true -> Pid ! {mc, errNameAlreadyExists};
                                            false -> NewListClients = ListClients++[{Name, Node, Pid}],
                                                     Pid ! {mc, addOk},
                                                     masterClient(NewListClients)
                                        end;
            {remove, Name} -> del = clientLookUp(Name, ListClients),
                              if del /= error -> masterClient(lists:delete(del, ListClients)) end
    end.
                              
                              

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













