{ config, pkgs, ... }:

with pkgs.lib;

let
  cfg = config.services.phpfpm;
  fpmCfgFile = pkgs.writeText "phpfpm.conf" fpmConf;
  fpmConf = ''
    [global]
    pid = ${cfg.stateDir}/php-fpm.pid
    error_log = ${cfg.logDir}/error.log
    daemonize = no

    ${pools}
  '';

  getPoolContent = pool: let
    iniEsc = val:
      if builtins.isString val then "\"${escape ["\""] val}\""
      else if val == true then "on"
      else if val == false then "off"
      else toString val;
    dotNS = ns: if ns != "" then (ns + ".") else "";
    traverse = p: ns: let
      travMap = key: val:
        if ns == "" && (key == "env" || (substring 0 4 key) == "php_") then
          let l = mapAttrsToList (k: v: "${key}[${k}] = ${iniEsc v}") val;
          in concatStringsSep "\n" l
        else if key == "value" then
          "${ns} = ${iniEsc val}"
        else if isAttrs val then
          traverse val "${dotNS ns}${key}"
        else "${dotNS ns}${key} = ${iniEsc val}";
    in concatStringsSep "\n" (mapAttrsToList travMap p);
  in traverse pool "";

  pools = let
    f = section: content: "[${section}]\n${getPoolContent content}";
  in concatStringsSep "\n\n" (mapAttrsToList f cfg.pools);

  fpmPackage = pkgs.php5_3fpm;
in {
  options = {
    services.phpfpm = {
      enable = mkOption {
        default = false;
        description = "Whether to enable the PHP FastCGI Process Manager.";
      };

      user = mkOption {
        default = "phpfpm";
        description = "User account under which PHP FPM runs.";
      };

      group = mkOption {
        default = "phpfpm";
        description = "Group under which PHP FPM runs.";
      };

      stateDir = mkOption {
        default = "/var/run/phpfpm";
        description = "State directory with PID and socket files.";
      };

      logDir = mkOption {
        default = "/var/log/phpfpm";
        description = "Directory where to put in log files.";
      };

      pools = mkOption {
        default = {
          default = {
            user = cfg.user;
            group = cfg.group;
            listen = "${cfg.stateDir}/default.socket";
            pm = {
              value = "dynamic";
              max_children = 400;
              min_spare_servers = 10;
              max_spare_servers = 30;
            };
          };
        };

        description = ''
          Specify the pools the FastCGI Process Manager should manage.

          This is specified by using an attribute set which maps roughly 1:1
          to ini-file syntax, with the exception that the main value of a
          namespace has to be specified by an attribute called 'value'.

          In addition, attributes called 'env' or starting with 'php_' are
          formatted with square brackets, like for example 'env[TMP] = /tmp',
          which corresponds to 'env.TMP = "/tmp"'.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    users.extraUsers = singleton {
      name = cfg.user;
      description = "PHP FastCGI user";
    };

    users.extraGroups = singleton {
      name = cfg.group;
    };

    jobs.phpfpm = {
      startOn = "started network-interfaces";
      stopOn = "stopping network-interfaces";
      #buildHook = "${fpmPackage}/sbin/php-fpm -t -y ${fpmCfgFile}";
      preStart = ''
        install -m 0755 -o "${cfg.user}" -g "${cfg.group}" -d "${cfg.stateDir}" "${cfg.logDir}"
        touch "${cfg.logDir}/error.log"
        chmod 0600 "${cfg.logDir}/error.log"
        chown "${cfg.user}:${cfg.group}" "${cfg.logDir}/error.log"
      '';
      exec = "${fpmPackage}/sbin/php-fpm -y ${fpmCfgFile}";
    };
  };
}
