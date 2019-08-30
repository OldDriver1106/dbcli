/*[[Show object privileges. Usage: @@NAME <object_name>
	--[[
		@CHECK_ACCESS_TAB: dba_tab_privs={dba} default={all}
		@CHECK_ACCESS_OWN: dba_tab_privs={OWNER} default={TABLE_SCHEMA}
	--]]
]]*/
ora _find_object "&V1" 1
set feed off
PRO DBA_TAB_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_TAB._tab_privs
where (&CHECK_ACCESS_OWN=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME);

PRO DBA_COL_PRIVS:
PRO ===============
select * from &CHECK_ACCESS_TAB._col_privs
where (&CHECK_ACCESS_OWN=:OBJECT_OWNER and TABLE_NAME=:OBJECT_NAME) 
OR upper(:V1) IN(GRANTEE,TABLE_NAME,COLUMN_NAME);

PRO DBA_ROLE_PRIVS:
PRO ===============
select * from DBA_ROLE_PRIVS WHERE upper(:V1) in(GRANTED_ROLE,GRANTEE);

PRO DBA_SYS_PRIVS:
PRO ===============
select * from DBA_SYS_PRIVS WHERE upper(:V1) in(GRANTEE,PRIVILEGE);
