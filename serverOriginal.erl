-module(server2).
-compile(export_all).   


dispatcher()->
    {ok,ListenSock} = gen_tcp:listen(8002,[{active,false}]),
    {ok,Sock} = gen_tcp:accept(ListenSock),
    loop_dispatcher(ListenSock, Sock).


loop_dispatcher(ListenSock, Sock)->
    Pid = spawn(?MODULE,psocket,[Sock]),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock, Sock).


psocket(Sock)->
%%    receive ok -> ok end,
    ok = inet:setopts(Sock,[{active,true}]),
    receive
        {tcp,Socket,Cmd} ->
            Respuesta = pcomando(Cmd),
            gen_tcp:send(Socket,Respuesta)
    end,
    psocket(Sock).


pcomando(Cmd)->
    "ERROR no implementado".

