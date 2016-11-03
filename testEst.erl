-module(testEst).
-compile(export_all).

-define(times, 10000).

%%srvInitTable = [{'srvA@jose-laptop',0}, {'srvB@jose-laptop',0}]

connectNodes(ListServers) ->
    lists:map(fun(Name) -> net_kernel:connect_node(Name) end, ListServers).

pstat(ListServers) ->
    register(stats, self()),
    loopPstat(ListServers).

loopPstat(ListServers) ->
    receive after 5000 -> {A, St} = erlang:statistics(reductions), 
                          lists:map(fun(Srv) -> {stats, Srv} ! {load, node(), self(), St} end, ListServers)
    end,
    loopPstat(ListServers).




%%auxiliar() ->
%%    net_kernel:connect_node('srvB@jose-laptop'),
%%    register(stats, self()),
%%    receive {load, Name, St, Pid} -> Pid ! {<<"recibido">>, St} end.

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
    register(stats, self()),
    receive 
        {load, NameSrv, PidSrv, St} -> NewSrvTable = lists:delete({NameSrv, getSrvLoad(SrvTable, NameSrv)}, SrvTable)++[{NameSrv, St}],
                                       pbalance(NewSrvTable);
        {req, Pid} -> Pid ! getSrvMinLoad(SrvTable),
                      pbalance(SrvTable)
    end.













