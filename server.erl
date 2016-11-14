-module(server).
-compile(export_all).   
-import(testEst, [pbalance/1, connectNodes/1]).

%% spawneamos el pbalance en el servidor local, apenas empieza el dispatcher (va a haber uno por nodo)
dispatcher()->
    {ok,ListenSock} = gen_tcp:listen(8000,[{active,false}]),
    connectNodes(['srvA@jose-laptop','srvB@jose-laptop']),
    PidPbalance = spawn(testEst, pbalance, [[{'srvA@jose-laptop',0},{'srvB@jose-laptop',0}]]),
%%  PidMasterClient = spawn(testEst, masterClient,[[]]),
    loop_dispatcher(ListenSock, PidPbalance).


loop_dispatcher(ListenSock, PidPbalance)-> %% Mantiene todos los clientes conectados a este server ClientList
    {ok,Sock} = gen_tcp:accept(ListenSock),
    Pid = spawn(?MODULE,psocket,[Sock, PidPbalance]),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock, PidPbalance).

%% Avisar masterClient que hay un nuevo cliente, mandar {add, {nombreCliente, node(), self()}}
%% Hay que pensar el modo de resolver si falla, y el nombre ya esta usado, habria que esperar una respuesta.
psocket(Sock, PidPbalance)->
    receive ok -> ok end,
    register(psocketx, self()), %% este nombre deberia ser unico por cada cliente.
    io:format("paso psocket\n"),
    looppsocket(Sock, PidPbalance).

%%ver lo del mensajito de respuesta de pbalance!!
looppsocket(Sock, PidPbalance) ->
    ok = inet:setopts(Sock,[{active,true}]),
    io:format("entro a looppsocket\n"),
    receive
           {tcp,Socket,Cmd} -> PidPbalance ! {req, self()},
                               io:format("mando peticion a pbalance\n"),
                               receive 
                                   {ans, Node} -> spawn(Node, server, pcomando, [Cmd, node()])
                               end;                            
%%                               spawn(?MODULE, pcomando, [Cmd, self()]);
           {pcomando, Respuesta} -> gen_tcp:send(Sock,Respuesta)
    end,
    looppsocket(Sock, PidPbalance).


pcomando(Cmd, Node)->
    io:format("antes del register pcomando\n"),
    register(pcomandox, self()),
    io:format("despues del register pcomando\n"),
%%    io:format("paso\n"),
    looppcomando(Cmd, Node).

%% deberia computar el Cmd, y devolverle una respuesta a psocket
looppcomando(Cmd, Node) ->
    {psocketx, Node} ! {pcomando, "Comando recibido"}.


%% 









