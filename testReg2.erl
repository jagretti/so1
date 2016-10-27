-module(testReg2).
-compile(export_all).

%% HERNAN

connectNodes() ->
    net_kernel:connect_node('omar@jose-laptop').

%% no anda
registerNodes(X) ->
    register(X, self()).

enviador() ->
    connectNodes(),
    register(grinch, self()),
    loopEnviador().

loopEnviador() ->
    {grinch, 'omar@jose-laptop'} ! {hello, "hola omarcito", self()}.
    
