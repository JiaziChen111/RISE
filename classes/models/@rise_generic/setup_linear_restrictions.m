function [a_func,a2tilde_func,restr_var_data_func,na2]=setup_linear_restrictions(obj)
if isa(obj,'stochvol')
    error('linear restrictions on stochastic volatility model need to be updated')
    % for the stochastic volatility obj, I may still want to do as before, i.e.
    % applying the zero restrictions to determine the list of the estimated
    % parameters and not the other way around as it is done here, i.e. use the
    % list of estimated parameters to determine the restriction matrices.
end
% system is Aa=b
LR=obj.options.estim_linear_restrictions;

a_func=@(x,~)x;
a2tilde_func=@(x,~)x;
estim_names=parser.param_name_to_valid_param_name({obj.estimation.priors.name});
% if constant paramater and analytical solution, keep only the ai and ci
% parameters
is_constant_parameter_var=isa(obj,'rfvar') && ...
        obj.markov_chains.regimes_number==1 && ...
        obj.options.vp_analytical_post_mode;
if is_constant_parameter_var
    [lag_names,lag_locs]=vartools.select_parameter_type(estim_names,'lag_coef');
    [det_names,det_locs]=vartools.select_parameter_type(estim_names,'det_coef');
    orig_estim_names=estim_names;
    estim_names=[lag_names,det_names];
    estim_locs=[lag_locs(:).',det_locs(:).'];
end
nparam=numel(estim_names);
na2=nparam;
R1i_r_0=0;
R1i_R2_I2=speye(nparam);
ievec=1:nparam;
if ~isempty(LR)
    lhs=[LR{:,1}];
    lhs=lhs(:);
    b=[LR{:,2}];
    b=b(:);
    [A,b]=linear_restrictions(lhs,b,obj,estim_names);
    % remove the rows with no restrictions
    bad_rows=~any(A,2);
    if any(bad_rows)
        disp(find(bad_rows))
        if any(b(bad_rows))
            error('no-restrictions rows with non-zero rhs')
        end
        warning('The no-restriction rows above are removed')
        A=A(~bad_rows,:);
        b=b(~bad_rows);
    end
    nrest=size(A,1);
    if rank(full(A))~=nrest
        error('Linear restriction matrix R (R*a=r) not of full rank. Probably some redundant restrictions')
    end
    [Q,R,evec]=qr(A,'vector');
    ievec=evec;
    ievec(evec)=1:nparam;
    
    r=Q'*b;
    % partitioning
    %-------------
    na1=nrest;
    na2=nparam-na1;
    R1=R(:,1:nrest);
    R2=R(:,nrest+1:end);
    if any(r)
        R1i_r_0=[R1\r;zeros(na2,1)];
    end
    R1i_R2_I2=[-R1\R2;eye(na2)];
    
    % finally memoize everything
    %---------------------------
    a_func=@get_alpha;
    a2tilde_func=@get_alpha2_tilde;
end
restr_var_data_func=@restricted_var_data_;

    function vd=restricted_var_data_(obj)
        [bigy,bigx,nv]=vartools.set_y_and_x(obj.data.y,obj.data.x,...
            obj.nlags,obj.constant);
        vd=struct();
        xi=kron(bigx',eye(nv));
        f=R1i_r_0;
        G=R1i_R2_I2;
        vd.ytilde=bigy(:);
        if any(f)
            vd.ytilde=vd.ytilde-xi*f(ievec);
        end
        vd.Xtilde=xi*G(ievec,:);
        %-----------------------
        if is_constant_parameter_var
            vd.orig_estim_names=orig_estim_names;
            vd.estim_names=estim_names;
            vd.estim_locs=estim_locs;
        end
    end

    function a=get_alpha(a2tilde,covflag)
        if nargin<2
            covflag=false;
        end
        % get atilde first then re-order it
        %----------------------------------
        if covflag
            atilde=R1i_R2_I2*a2tilde*R1i_R2_I2';
            a=atilde(ievec,ievec);
        else
            atilde=R1i_r_0+R1i_R2_I2*a2tilde;
            a=atilde(ievec);
        end
    end

    function a2tilde=get_alpha2_tilde(a,covflag)
        if nargin<2
            covflag=false;
        end
        % get atilde first then extract the relevant part
        %------------------------------------------------
        if covflag
            atilde=a(evec,evec);
            a2tilde=atilde(na1+1:end,na1+1:end);
        else
            atilde=a(evec);
            a2tilde=atilde(na1+1:end);
        end
    end
end

% function [obj,linear_restrictions]=apply_zero_restrictions(obj)
% if isempty(obj)
%     obj=struct('restrict_lags',{{}},'estim_linear_restrictions',{{}});
%     return
% end
% if ~strcmp(class(obj),'svar') %#ok<STISA>
%     return
% end
% linear_restrictions=obj.options.restrict_lags;
% param_template=obj.param_template;
% if ~isempty(linear_restrictions)
%     [nrest,ncols]=size(linear_restrictions);
%
%     processed=false(nrest,1);
%
%     % phase one apply the simple restrictions
%     %----------------------------------------
%     myconvert=@(z)int2str(locate_variables(z,obj.endogenous.name));
%     operators={'+','-','*','/','^'};
%     linear_restrictions(:,1)=svar.reformat_restriction(linear_restrictions(:,1),myconvert);
%     for irest=1:nrest
%         right=0;
%         if ncols>1
%             right=linear_restrictions{irest,2};
%         end
%         processed(irest)=apply_restriction(linear_restrictions{irest,1});
%     end
%     linear_restrictions=translate_svar_restrictions(linear_restrictions(~processed,:));
% end
% obj.estim_linear_restrictions=linear_restrictions;
% obj.estim_param_template=param_template;
%
%     function flag=apply_restriction(x)
%         flag=false;
%         % do not process if there is an operator
%         %---------------------------------------
%         for iop=1:length(operators)
%             has_operator=any(x==operators{iop});
%             if has_operator
%                 return
%             end
%         end
%         [a_loc,eqtn_loc,var_loc]=svar.decompose_parameter(x,obj.param_template(1,:));
%         param_template{2,a_loc}(eqtn_loc,var_loc)=right;
%         flag=true;
%     end
%
%     function restrictions=translate_svar_restrictions(restrictions)
%         % two things have to be done
%         % 1- translate the remaining restrictions to form sparse matrices
%         % of restrictions to be used during estimation
%         names=obj.parameters.name;
%         var_list=splanar.initialize(names,names);
%         for irest_=1:size(restrictions,1)
%             occur=regexp(restrictions{irest_,1},'\w+','match');
%             args=ismember(names,occur);
%             func=cell2mat(strcat(names(args),','));
%             func=str2func(['@(',func(1:end-1),')',restrictions{irest_,1}]);
%             args=var_list(args);
%             zz=func(args{:});
%             restrictions{irest_,1}=sparse(str2num(char(diff(zz,(1:obj.parameters.number))))); %#ok<ST2NM>
%         end
%     end
%
% end
%         underscores=find(x=='_');
%         aa=x(1:underscores(1)-1);
%         a_loc= strcmp(aa,param_template(1,:));
%         eqtn_loc=str2double(x(underscores(1)+1:underscores(2)-1));
%         var_loc=str2double(x(underscores(2)+1:end));
% put in the form {lag,eqtn,var}
%         x=regexprep(x,'a(\w+)\((\d+),(\w+)\)','{$1,$2,${myconvert($3)}}');
%         x=regexprep(x,'a(\w+)\((\w+),(\w+)\)','{$1,${myconvert($2)},${myconvert($3)}}');