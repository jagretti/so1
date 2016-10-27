-module(testRegister).
-compile(export_all).

escuchador() ->
    receive {Pid, Msg} -> Pid ! "Recibi "++Msg end,
    escuchador(). 
