-module(server).
-compile(export_all).   


dispatcher()->
    {ok,ListenSock} = gen_tcp:listen(8002,[{active,false}]),
    loop_dispatcher(ListenSock).


loop_dispatcher(ListenSock)->
    {ok,Sock} = gen_tcp:accept(ListenSock),
    Pid = spawn(?MODULE,psocket,[Sock]),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock).


psocket(Sock)->
    receive ok -> ok end,
    looppsocket(Sock).

looppsocket(Sock) ->
    ok = inet:setopts(Sock,[{active,true}]),
    receive
           {tcp,Socket,Cmd} -> spawn(?MODULE, pcomando, [Cmd, self()]);
%%            Respuesta = pcomando(Cmd),
%%            gen_tcp:send(Socket,Respuesta)            
%%        Pid o Nombre ! mensaje
           {pcomando, Pidsend, Respuesta} -> gen_tcp:send(Sock,Respuesta)
    end,
    looppsocket(Sock).


pcomando(Cmd, Pid)->
    Pid ! {pcomando, self(), "Comando recibido"}.

