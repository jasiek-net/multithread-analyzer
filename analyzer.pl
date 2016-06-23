:- ensure_loaded(library(lists)).
:- set_prolog_flag(single_var_warnings, off).
:- op(700, xfx, <>).

%% State description
%% State is represented by list with two elements:
%% 	 - Vars
%% 	 - Count
%% 1. Vars is prolog list with queue implemented like on moodle.
%% 	Variables are represented by pairs variable_name-value.
%% 	It's the same for arrays and simple variables
%% 	Example: [x-1, y-2, arr-[0,1,3], pid-1]
%% 2. Count is prolog list with instructions counter.
%% 	It keeps for all processes number of next instruction,
%% 	in cell corresponding to the pid number.
%% Before execution step() pid value in Vars is changing
%% to pid for the actual process.

%% Initialization
initVars([], [pid-0]).
initVars([Var | Vars], [Var-0 | Inited]) :- initVars(Vars, Inited).

fillZero(0, []).
fillZero(N, Arr) :-	
	M is N - 1,
	fillZero(M, Tail),
	Arr = [0 | Tail], !.

initArray([], _, []).
initArray([Var | Vars], N, [Var-Arr | Inited]) :-
	initArray(Vars, N, Inited),
	fillZero(N, Arr).

%% Main program
verify(N, File) :-
	((integer(N), N > 0) ->
		catch(open(File, read, Str), _,
			(write('Error: no file named - '), write(File), fail)),
			read(Str, vars(Vars)),
			read(Str, arrays(Arrays)),
			read(Str, program(Program)),
			close(Str),
			initState([Vars, Arrays], N, InitState),
			(dfs(Program, InitState, [], 0) -> 
			write('Program is incorrect'), nl
			;
			write('Program is correct (safe)'), nl)
	;
		write('Error: parameter 0 should be number > 0'), 
		fail
	).

initState([Vars, Arrs], N, InitState) :-
	initVars(Vars, InitVars),
	initArray(Arrs, N, InitArrs),
	fillZero(N, Count),
	append(InitArrs, InitVars, State),
	InitState = [State, Count].

%% DFS implementation
%% If new state is in all visited states we cut branch
dfs(Program, [Vars, Count], States, PrId) :-
	(insection(Program, Count, InSect), InSect > 1 ->
		!
		%% TODO: show trace and processes pids
	;
		replaceByValue(pid-_, pid-PrId, Vars, SetPid),
		step(Program, [SetPid, Count], PrId, StateOut),
		(member(StateOut, States) -> 
			NewId is PrId + 1,
			dfs(Program, [Vars, Count], States, NewId)
			;
			dfs(Program, StateOut, [StateOut | States], 0))
	).

%% Step logic
%% Get number of next instruction from Count(er)
%% Get instruction from Program (by Step)
%% Evaluate instruction
step(Program, [Vars, Count], PrId, StateOut) :-
	nth0(PrId, Count, Step),
	nth0(Step, Program, Instruction),
	evalInstr(Instruction, [Vars, Count], PrId, StateOut).

insection(Program, Count, Result) :-
	nth0(SectionNumber, Program, sekcja),
	count(SectionNumber, Count, Result), !.

nextStep(PrId, Count, News) :-
	nth0(PrId, Count, Old),
	New is Old + 1,
	replaceByIndex(PrId, New, Count, News), !.

%% Evaluation of instructions
evalInstr(sekcja, [Vars, Count], PrId, [Vars, News]) :-
	nextStep(PrId, Count, News), !.

evalInstr(goto(Number), [Vars, Count], PrId, [Vars, News]) :-
	New is Number - 1,
	replaceByIndex(PrId, New, Count, News), !.

evalInstr(condGoto(Exp, Number), [Vars, Count], PrId, [Vars, News]) :-
	evalLogic(Exp, Vars, Result),
	(Result ->
		New is Number - 1,
		replaceByIndex(PrId, New, Count, News);
		nextStep(PrId, Count, News)).

evalInstr(assign(arr(Id, ExpA), Exp), [Vars, Count], PrId, [NewV, NewC]) :-
	evalArythm(Exp, Vars, New),
	evalArythm(ExpA, Vars, Index),
	replaceByIndex(Index, New, OldArr, NewArr),
	replaceByValue(Id-OldArr, Id-NewArr, Vars, NewV),
	nextStep(PrId, Count, NewC), !.

evalInstr(assign(Ident, Exp), [Vars, Count], PrId, [NewVar, NewCount]) :-
	evalArythm(Exp, Vars, New),
	replaceByValue(Ident-_, Ident-New, Vars, NewVar),
	nextStep(PrId, Count, NewCount), !.

%% Logic operation
logicOp(=, ==).
logicOp(<, <).
logicOp(<>, \==).

evalLogic(Exp, State, Result) :-
	Exp =.. [Op, S1, S2],
	logicOp(Op, Oper),
	evalSimple(S1, State, R1),
	evalSimple(S2, State, R2),
	Calc =.. [Oper, R1, R2],
	(Calc -> Result = true; Result = false).

%% Arythmetic operation
arythOp(+, +).
arythOp(-, -).
arythOp(*, *).
arythOp(/, div).

evalArythm(Exp, State, Result) :-
	Exp =.. [Op, S1, S2],
	arythOp(Op, Oper),
	evalSimple(S1, State, R1),
	evalSimple(S2, State, R2),
	Calc =.. [Oper, R1, R2],
	Result is Calc, !.
	
evalArythm(Exp, State, Result) :-
	evalSimple(Exp, State, Result).

%% Simple - getting value of variables (arrays & simple)
evalSimple(arr(Ident, ExpArythm), State, Result) :- 
	evalArythm(ExpArythm, State, Index),
	member(Ident-Array, State),
	nth0(Index, Array, Result), !.

evalSimple(Ident, State, Result) :-
	member(Ident-Result, State), !.

evalSimple(Number, _, Number) :- 
	integer(Number).

%% HELPERS:

%% Arguments: OldValue, NewValue, List, NewList
replaceByValue(_, _, [], []).
replaceByValue(O, R, [O|T], [R|T2]) :- replaceByValue(O, R, T, T2).
replaceByValue(O, R, [H|T], [H|T2]) :- 
	H \= O, 
	replaceByValue(O, R, T, T2).

%% Arguments: Index, NewValue, List, NewList
%% Elements indexed from 0
replaceByIndex(0, X, [_|T], [X|T]).
replaceByIndex(I, X, [H|T], [H|R]):- 
	I > -1, NI is I-1, 
	replaceByIndex(NI, X, T, R), !.

%% Count 
count(_, [], 0).
count(X, [X | T], N) :- !, count(X, T, N1), N is N1 + 1.
count(X, [_ | T], N) :- count(X, T, N).
