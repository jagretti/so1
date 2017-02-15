-module(gameLogic).
-compile(export_all).

move(M, {T1, T2}, Player) -> case ((M > 0) and (M < 10)) of
                                 true -> Move = trunc(math:pow(2,M-1)),
                                         case validMove(Move, T1, T2) of
                                             true -> case Player of
                                                         1 -> {Move+T1, T2};            
                                                         2 -> {T1, Move+T2}                                                     
                                                     end;
                                             false -> error
                                         end;
                                 false -> error
                             end.


validMove(Move, T1, T2) -> (((Move band T2) == 0) and ((Move band T1) == 0)).

%% Asumimos que siempre el movimiento se corresponde al tablero 1 (hacer esto bien en el pcomando)

winGame(X) -> case X of
                  7 -> true;
                  273 -> true;
                  73 -> true;
                  146 -> true;
                  84 -> true;
                  292 -> true;
                  56 -> true;
                  448 -> true;
                  _ -> false
              end.

makeMatrix({T1, T2}) -> ListT1 = lists:map(fun(N) -> case (trunc(math:pow(2, N-1)) band T1) of 
                                                          0 -> integer_to_list(N);
                                                          M -> "X" 
                                                      end 
                                            end, lists:seq(1,9)),
                        ListT2 = lists:map(fun(N) -> case (trunc(math:pow(2, N-1)) band T2) of 
                                                          0 -> integer_to_list(N);
                                                          M -> "O" 
                                                      end 
                                            end, lists:seq(1,9)),
                        ListMerge = lists:map(fun(N) -> case (lists:nth(N, ListT1)) of
                                                            "X" -> "X";
                                                            M -> lists:nth(N, ListT2)
                                                        end
                                              end, lists:seq(1,9)).

printMatrix(ListBoard) -> io:fwrite("~nTablero:~n-------~n~n ~s ~s ~s~n ~s ~s ~s~n ~s ~s ~s~n ~n",[lists:nth(1,ListBoard),lists:nth(2,ListBoard),lists:nth(3,ListBoard),lists:nth(4,ListBoard),lists:nth(5,ListBoard),lists:nth(6,ListBoard),lists:nth(7,ListBoard),lists:nth(8,ListBoard),lists:nth(9,ListBoard)]).


                       %  Hacer map numerando los espacios vacios de la union de ambos tableros   








