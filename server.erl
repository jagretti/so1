-module(server).
-compile(export_all).   
-import(testEst, [pbalance/1, connectNodes/1, masterClient/1, pstat/1]).

%% spawneamos el pbalance en el servidor local, apenas empieza el dispatcher (va a haber uno por nodo)
dispatcher()->
    {ok,ListenSock} = gen_tcp:listen(8003,[{active,false}]),
    connectNodes(['srvA@jose-laptop','srvB@jose-laptop']),
    PidPstat = spawn(testEst, pstat, [['srvA@jose-laptop','srvB@jose-laptop']]),
    PidPbalance = spawn(testEst, pbalance, [[{'srvA@jose-laptop',0},{'srvB@jose-laptop',0}]]),
%    io:format("Anteesss \n"),
    PidMasterClient = spawn(testEst, masterClient,[[],['srvA@jose-laptop','srvB@jose-laptop']]),
%    io:format("Despues \n"),
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient).


loop_dispatcher(ListenSock, PidPbalance, PidMasterClient)-> %% Mantiene todos los clientes conectados a este server ClientList
    {ok,Sock} = gen_tcp:accept(ListenSock),
    io:format("Acepto conexion\n"),
    Pid = spawn(?MODULE,psocket,[Sock, PidPbalance, PidMasterClient]),
    io:format("Hizo spawn del psocket\n"),
    ok = gen_tcp:controlling_process(Sock,Pid),
    Pid!ok,
    loop_dispatcher(ListenSock, PidPbalance, PidMasterClient).

%% Avisar masterClient que hay un nuevo cliente, mandar {add, {nombreCliente, node(), self()}}
%% Hay que pensar el modo de resolver si falla, y el nombre ya esta usado, habria que esperar una respuesta.
%% HACER RECEIVE DEL COMANDO CON hernan, y habria que tomar ese nombre para preguntarle al masterClient
psocket(Sock, PidPbalance, PidMasterClient) ->
    io:format("Entre a psocket\n"),
    receive ok -> ok end,
    io:format("pase el ok\n"),
    ok = inet:setopts(Sock,[{active,true}]),
    receive
        {tcp, Socket, Msg} -> case string:str(string:strip(Msg),"CON") of
                                  1 -> PidMasterClient ! {add, {string:substr(string:strip(Msg),5), node(), self()}},
                                       io:format("Entro guarda 1 psocket\n"),
                                       receive 
                                           {mc, addOk} -> gen_tcp:send(Socket, ">> Conexion establecida correctamente :) << \n"),
                                                          looppsocket(Sock, PidPbalance);
                                           {mc, errNameAlreadyExists} -> gen_tcp:send(Socket, "***Error: Nombre ya existe"),
                                                                         self() ! ok,
                                                                         psocket(Sock, PidPbalance, PidMasterClient)
                                       end;
                                  N -> gen_tcp:send(Socket, "***Error: se esperaba el comando CON"),
                                       io:format("Entro guarda 1 psocket\n"),
                                       self() ! ok,
                                       psocket(Sock, PidPbalance, PidMasterClient)
                              end
    end.
    
%%    PidMasterClient ! {add, {
%%    io:format("paso psocket\n"),
%%    .

%%ver lo del mensajito de respuesta de pbalance!!
looppsocket(Sock, PidPbalance) ->
%%    ok = inet:setopts(Sock,[{active,true}]),
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









