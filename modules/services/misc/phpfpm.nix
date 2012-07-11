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

    [default]
    user = ${cfg.user}
    group = ${cfg.group}

    listen = ${cfg.stateDir}/default.socket
    pm = dynamic
    pm.max_children = 400
    pm.min_spare_servers = 10
    pm.max_spare_servers = 30
  '';

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
