-module(prueba).
-compile(export_all).

sesion(Sock) ->
    receive ok -> ok end,
    io:format("session: ~w || ~w ~n", [self(), Sock]),
    ok = inet:setopts(Sock, [{active, true}]),
    %% {ok, Bin} = gen_tcp:recv(Sock, 0),
    receive
        {tcp, _S, <<109,111,114,105,116,101>>} -> gen_tcp:close();
        {tcp, _S, Msg} -> io:format("sesion: llega [~w]~n", [Msg]);
        X -> io:format("sesion [[~w]]~n", [X])
    end,
    %%ok = gen_tcp:close(Sock).
    self() ! ok,
    sesion(Sock).
    


init() ->
    io:format("init: ~w~n", [self()]),
    {ok, LSock} = gen_tcp:listen(6668, [binary, {packet, 0}, {active, true}]),
    {ok, Sock} = gen_tcp:accept(LSock),
    Pid = spawn(?MODULE, sesion, [Sock]),
    ok = gen_tcp:controlling_process(Sock, Pid),
    Pid ! ok,
    receive     
        {tcp, _S, Msg} -> io:format("init: llega [~w]~n", [Msg]);
        X -> io:format("init [[~w]]~n", [X])
    end,
    ok = gen_tcp:close(LSock).
