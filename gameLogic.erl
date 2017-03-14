-module(gameLogic).
-compile(export_all).

% M representa la posición en el tablero
move(M, {T1, T2}, Player) -> case ((M > 0) and (M < 10)) of
                                 true -> Move = trunc(math:pow(2,M-1)),
                                         case validMove(Move, T1, T2) of
                                             true -> case Player of
                                                         1 -> {NT1,NT2} = {Move+T1, T2};            
                                                         2 -> {NT1,NT2} = {T1, Move+T2}                                                     
                                                     end,
                                                     case (NT1 + NT2) of
                                                         511 -> case (winGame(NT1)) of
                                                                    true -> {NT1,NT2};
                                                                    false -> case (winGame(NT2)) of
                                                                                 true -> {NT1,NT2};
                                                                                 false -> {empate, {NT1,NT2}}
                                                                             end
                                                                end;  
                                                         _ -> {NT1,NT2}
                                                     end;
                                             false -> error
                                         end;
                                 false -> error
                             end.


validMove(Move, T1, T2) -> (((Move band T2) == 0) and ((Move band T1) == 0)).


winGame(X) -> List1 = lists:map(fun(N) -> case (andList(makeIntMatrix(X),makeIntMatrix(N)) == makeIntMatrix(N)) of 
                                                          true -> 1;
                                                          false -> 0 
                                                      end 
                                          end, [7,273,73,146,84,292,56,448]),
              case (List1 == [0,0,0,0,0,0,0,0]) of
                    true -> false;
                    false -> true
              end.
              

andList([],[]) -> [];
andList([X | XS],[Y | YS]) -> [X band Y] ++ andList(XS,YS).

makeIntMatrix(T1) -> ListT1 = lists:map(fun(N) -> case (trunc(math:pow(2, N-1)) band T1) of 
                                                          0 -> 0;
                                                          M -> 1 
                                                      end 
                                            end, lists:seq(1,9)).



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




