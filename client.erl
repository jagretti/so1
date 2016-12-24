-module(client).
-compile(export_all).


client()->
%    Hostname = "localhost",
    {ok,Sock} = gen_tcp:connect("localhost", 8003, [binary, {packet,0}]),
    
    ok = gen_tcp:send(Sock,"CON hernan"),
    
    receive
        {tcp,Sock,Msg} ->
            io:format("~p~n",[Msg])
    end.
