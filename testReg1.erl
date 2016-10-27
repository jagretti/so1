-module(testReg1).
-compile(export_all).

%% OMAR

connectNodes() ->
    net_kernel:connect_node('hernan@jose-laptop').

%% no anda
registerNodes(X) ->
    register(X, self()).

escuchador() ->
    connectNodes(),
    register(grinch,self()),
    loopEscuchador().

loopEscuchador() ->
    receive {hello, Msg, Pid} -> Pid ! <<"recibido">> end,
    loopEscuchador(). 
