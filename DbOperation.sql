
/*使用说明：
1 提交脚本
2 在"配置开始"处，配置路径
3 在"操作开始"处，执行想做的操作

删除、还原等影响现有数据库的操作已被注释
*/
use master
go

------------------------------------------------------
if object_id(N'tempdb..#db_cfg', N'U') is not null
    drop table #db_cfg
go

create table #db_cfg
(
    id        int identity(1, 1),
    name      varchar(20),  --设备名         引用方式: @name
    file_path varchar(500), --数据库文件     引用方式: @iamge
    log_path  varchar(500), --数据库日志文件 引用方式: @log
    dump_path varchar(500), --备份文件       引用方式: @dump
    mo_path varchar(500),
)

--------------------------------配置开始-------------------------------
truncate table #db_cfg
insert #db_cfg (name, file_path, log_path, mo_path, dump_path)
       select   'mydb01',
--                'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb01.mdf', 'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb01.ldf', 'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb01_memory',--[sql2014mo]
                'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb01.mdf', 'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb01.ldf', '', --[sql2008]

                'D:\mssql\MSSQL10_50.FIRST\MSSQL\backup\mydb01.dump'
       union all
       select   'mydb02',
                'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb02.mdf', 'D:\mssql\MSSQL10_50.FIRST\MSSQL\Data\mydb02.ldf', '',
                'D:\mssql\MSSQL10_50.FIRST\MSSQL\backup\mydb02.dump'


--select * from #db_cfg
--------------------------------配置结束-------------------------------

--------------------------------操作开始-------------------------------
/*
--创建登录用户
create_login 'wtzc_dbo'

--创建数据库, 数据库存在则不创建
create_db 'sa'

--创建备份设备
create_device

--删除数据库	
--drop_db

--备份数据库到dump_path
backup_db_path

--从dump_path恢复数据库
--restore_db_path

--备份数据库到备份设备
backup_db_device

--从备份设备恢复数据库
--restore_db_device

--分离数据库
detach_db

--附加数据库
attach_db

--------附加操作, 一般不用, 已包含在create_db中---------
--更改数据库恢复模式
set_recovery 'simple'

--设置数据库所有者
set_owner 'wtzc_dbo'

--*/
--------------------------------操作结束-------------------------------



------------------------------------------------------
if object_id(N'tracert_db_cfg', N'P') is not null
    drop proc tracert_db_cfg
go

create proc tracert_db_cfg
    @p_sql varchar(1024),
    @p_oper varchar(10) = 'common'--create:create database, drop:drop database
as
    declare @id int, @sql varchar(1024), @name varchar(20),
            @image varchar(500), @log varchar(500), @dump varchar(500), @backup_device varchar(50),
            @mo_path varchar(500), @mo_sql varchar(500)

    select @id = 0
    while 1 = 1
    begin
        --取引用参数的实际值
        select top 1 @id = id, @name = name, @image = file_path, @log = log_path, @dump = dump_path, @mo_path = mo_path
        from #db_cfg
        where id > @id
        order by id

        if @@rowcount = 0
            break

        -- 加入内存数据库恢复脚本
        if @mo_path != '' and (lower(@p_sql) like '%restore database%')
        begin
          select @sql = replace(@p_sql, 'nounload', 'MOVE N''@name_memory'' to N''@mo_path, nounload''')
          --print @sql
        end
        else
        begin
          select @sql = @p_sql
        end

        --替换引用参数
        select @sql = replace(@sql, '@name', @name)
        select @sql = replace(@sql, '@image', @image)
        select @sql = replace(@sql, '@log', @log)
        select @sql = replace(@sql, '@dump', @dump)
        select @sql = replace(@sql, '@mo_path', @mo_path)

        --需要特殊处理的操作
        if @p_oper = 'create'--创建数据库，数据库已存在则不操作
        begin
             if exists(select * from sys.databases where name = @name)
                continue

             if @mo_path != ''
             begin
                select @mo_sql =
', filegroup fg1 contains memory_optimized_data(name=''' + @name + '_memory'', filename=''' + @mo_path + ''') '
                select @sql = replace(@sql, '[mo]', @mo_sql)
             end
             else
                select @sql = replace(@sql, '[mo]', '')
        end
        else if @p_oper = 'drop'--删除数据库，数据库不存在则不操作
        begin
            if not exists(select * from sys.databases where name = @name)
                continue
        end
        else if @p_oper = 'dump'--创建备份设备，设备已存在则先删除
        begin
            select @backup_device = @name + '_backup'
            if exists(select * from sys.backup_devices where name = @backup_device)
                exec sp_dropdevice @backup_device
        end

        exec (@sql)
        --select @sql
    end
go

------------------------------------------------------
if object_id(N'create_login', N'P') is not null
    drop proc create_login
go

create proc create_login
    @p_login varchar(200)
as
    if not exists (select * from master..syslogins where name = @p_login)
  begin
    declare @sql varchar(max)
    set @sql = 'create login ' + @p_login + ' with password = ''' + @p_login + ''', default_database=[master], check_expiration=off, check_policy=off'
    exec(@sql)
  end
go

------------------------------------------------------
if object_id(N'create_db', N'P') is not null
    drop proc create_db
go

create proc create_db
    @p_login varchar(200)
as
    --创建数据库
    declare @sql varchar(1024)
    select @sql =
'
create database @name
on primary (name = @name_data, filename = ''@image'', size = 10, filegrowth = 10) [mo]
log on ( name = @name_log, filename = ''@log'', size = 10, filegrowth = 10)
'

    exec tracert_db_cfg @sql, 'create'

    --配置数据库恢复模式simple
    exec set_recovery 'simple'

    --设置数据库所有者wtzc_dbo
    exec set_owner @p_login
go

------------------------------------------------------
if object_id(N'set_recovery', N'P') is not null
    drop proc set_recovery
go

create proc set_recovery
    @p_mode varchar(200) --simple, bulk-logged, full
as
    declare @c_sql varchar(1024)
    select @c_sql = 'alter database @name set recovery ' + @p_mode
                   + char(1) + ';alter database @name set ansi_nulls on'
                   + char(1) + ';alter database @name set quoted_identifier on'
                   + char(1) + ';alter database @name set ansi_warnings on'
                   + char(1) + ';alter database @name set ansi_padding on'

    exec tracert_db_cfg @c_sql
go

------------------------------------------------------
if object_id(N'set_owner', N'P') is not null
    drop proc set_owner
go

create proc set_owner
    @p_login varchar(200)
as
    --设置数据库所有者wtzc_dbo
    declare @o_sql varchar(1024)
    select @o_sql = 'alter authorization on Database::@name to ' + @p_login
    exec tracert_db_cfg @o_sql
go

------------------------------------------------------
if object_id(N'create_device', N'P') is not null
    drop proc create_device
go

create proc create_device
as
    --添加备份设备
    declare @add_sql varchar(1024)
    select @add_sql = 'exec sp_addumpdevice ''disk'', ''@name_backup'', ''@dump'''
    exec tracert_db_cfg @add_sql, 'dump'
go

------------------------------------------------------
if object_id(N'drop_db', N'P') is not null
    drop proc drop_db
go

create proc drop_db
as
    declare @d_sql varchar(1024)
    select @d_sql = 'drop database @name'
    exec tracert_db_cfg @d_sql, 'drop'
go

------------------------------------------------------
if object_id(N'backup_db_path', N'P') is not null
    drop proc backup_db_path
go

create proc backup_db_path
as
    declare @b_sql varchar(1024)
    select @b_sql = 'backup database @name to disk = ''@dump'' with init, format'
    exec tracert_db_cfg @b_sql
go

------------------------------------------------------
if object_id(N'restore_db_path', N'P') is not null
    drop proc restore_db_path
go

create proc restore_db_path
as
    declare @re_sql varchar(1024)
    select @re_sql =
    '
    restore database @name from disk = ''@dump'' with file = 1, replace,
    move ''@name_data'' to ''@image'',
    move ''@name_log'' to ''@log'',
    nounload,  stats = 10
    '
    exec tracert_db_cfg @re_sql

    --update mydb01..czyb set czymm = 'k0g6d4c7baae2d27922f'
    --update mydb01..yybb set ip = '127.0.0.1', ip_hb = '127.0.0.1'
go

------------------------------------------------------
if object_id(N'backup_db_device', N'P') is not null
    drop proc backup_db_device
go

create proc backup_db_device
as
    declare @b2d_sql varchar(1024)
    select @b2d_sql = 'backup database @name to @name_backup with init'
    exec tracert_db_cfg @b2d_sql
go

------------------------------------------------------
if object_id(N'restore_db_device', N'P') is not null
    drop proc restore_db_device
go

create proc restore_db_device
as
    declare @rfd_sql varchar(1024)
    select @rfd_sql = 'restore database @name from @name_backup with replace'
    exec tracert_db_cfg @rfd_sql
go

------------------------------------------------------
if object_id(N'detach_db', N'P') is not null
    drop proc detach_db
go

create proc detach_db
as
    declare @rfd_sql varchar(1024)
    select @rfd_sql = 'sp_detach_db @dbname = @name'
    exec tracert_db_cfg @rfd_sql
go

------------------------------------------------------
if object_id(N'attach_db', N'P') is not null
    drop proc attach_db
go

create proc attach_db
as
    declare @rfd_sql varchar(1024)
    select @rfd_sql =
'create database @name on (filename = ''@image''), ( filename = ''@log'' ) for attach'

    exec tracert_db_cfg @rfd_sql
go

