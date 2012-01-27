%% Copyright (c) 2011 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Syslog backend for lager.

-module(lager_syslog_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
        code_change/3]).

-record(state, {level,facility,formatter,format_config}).

-include_lib("lager/include/lager.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% @private
init([Ident, Facility, Level]) ->
	init([Ident,Facility,Level,{lager_default_formatter,[]}]);
init([Ident, Facility, Level, Format]) ->
    case application:start(syslog) of
        ok ->
            init2(Ident, Facility, Level,Format);
        {error, {already_started, _}} ->
            init2(Ident, Facility, Level,Format);
        Error ->
            Error
    end.

init2(Ident, Facility, Level,{Formatter,Config}) ->
    case syslog:open(Ident, [pid], Facility) of
        ok ->
            {ok, #state{level=lager_util:level_to_num(Level),
						facility=Facility,
						formatter=Formatter, 
						format_config=Config}};
        Error ->
            Error
    end.

%% @private
handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    {ok, ok, State#state{level=lager_util:level_to_num(Level)}};
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event(#lager_log_message{severity_as_int=Level}=Message, #state{formatter=Formatter}=State) ->
    case lager_backend_utils:is_loggable(Message, State#state.level, {?MODULE,State#state.facility}) of
		true -> 
			Msg=Formatter:format(Message,State#state.format_config),
			% syslog doesn't handle full iolists, which the formatter can return
			% so convert it to a straight up list
			ok=syslog:log(convert_level(Level),binary_to_list(iolist_to_binary(Msg)) );
%%  			ok=syslog:log(convert_level(Level),Msg);
		_ -> ok
	end,
    {ok, State};
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
    application:stop(syslog),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

convert_level(?DEBUG) -> debug;
convert_level(?INFO) -> info;
convert_level(?NOTICE) -> notice;
convert_level(?WARNING) -> warning;
convert_level(?ERROR) -> err;
convert_level(?CRITICAL) -> crit;
convert_level(?ALERT) -> alert;
convert_level(?EMERGENCY) -> emerg.

-ifdef(TEST).

-define(MESSAGE_TEXT,"Test Message").
-define(TEST_FACILITY,"Test").
-define(TEST_MESSAGE(Level,Destinations),
		#lager_log_message{
						   destinations=Destinations,
						   metadata=[],
						   severity_as_int=Level,
						   timestamp=lager_util:format_time(),
						   message= ?MESSAGE_TEXT}).

-define(TEST_STATE(Level),#state{facility=?TEST_FACILITY,format_config=[message],formatter=lager_default_formatter,level=Level}).

% just in case you want to test that it actually goes to syslog
 log_test() ->
 	{ok,_}=init(["Lager",local0,debug]),
     ?MODULE:handle_event(?TEST_MESSAGE(?EMERGENCY,[]), #state{format_config=[],formatter=lager_default_formatter,level=?DEBUG}).
	
calls_syslog_test_() ->
	{foreach, fun() -> erlymock:start(),
					   erlymock:o_o(syslog,log,[info,?MESSAGE_TEXT]),
					   erlymock:replay()
	 end,
	 fun(_) -> ok end,
	 [{"Test normal logging" ,
	   fun() ->
			   ?MODULE:handle_event(?TEST_MESSAGE(?INFO,[]), ?TEST_STATE(?INFO)),
			   % make sure that syslog:log was called with the test message
			   erlymock:verify()
	   end
	  },
	  {"Test logging by direct destination",
	   fun() ->
			   ?MODULE:handle_event(?TEST_MESSAGE(?INFO,[{?MODULE,?TEST_FACILITY}]), ?TEST_STATE(?ERROR)),
			   % make sure that syslog:log was called with the test message
			   erlymock:verify()
	   end
	  }
	 ]}.

should_not_log_test_() ->
	{foreach, fun() -> erlymock:start(),
					   erlymock:stub(syslog,log,['_','_'], [{throw,should_not_be_called}]),
					   erlymock:replay()
	 end,
	 fun(_) -> ok end,
	 [{"Rejects based upon severity threshold" ,
	   fun() ->
			   ?MODULE:handle_event(?TEST_MESSAGE(?DEBUG,[]), ?TEST_STATE(?INFO)),
			   erlymock:verify()
	   end
	  }
	 ]}.


-endif.
