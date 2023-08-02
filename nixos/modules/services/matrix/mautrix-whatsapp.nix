{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mautrix-whatsapp;
  dataDir = "/var/lib/mautrix-whatsapp";
  registrationFile = "${dataDir}/whatsapp-registration.yaml";
  settingsFile = "${dataDir}/config.json";
  settingsFileUnsubstituted = settingsFormat.generate "mautrix-whatsapp-config-unsubstituted.json" cfg.settings;
  settingsFormat = pkgs.formats.json {};
in {
  options.services.mautrix-whatsapp = {
    enable = mkEnableOption "mautrix-whatsapp, a puppeting/relaybot bridge between Matrix and WhatsApp.";

    settings = mkOption rec {
      apply = recursiveUpdate default;
      inherit (settingsFormat) type;

      default = {
        homeserver = {
          domain = config.services.matrix-synapse.settings.server_name;
        };
        appservice = rec {
          address = "http://localhost:${toString port}";
          hostname = "[::]";
          port = 29318;
          database = {
            type = "sqlite3";
            uri = "${dataDir}/mautrix-whatsapp.db";
          };
          id = "whatsapp";
          bot = {
            username = "whatsappbot";
            displayname = "WhatsApp Bridge Bot";
          };
          as_token = "";
          hs_token = "";
        };
        bridge = {
          username_template = "whatsapp_{{.}}";
          displayname_template = "{{if .BusinessName}}{{.BusinessName}}{{else if .PushName}}{{.PushName}}{{else}}{{.JID}}{{end}} (WA)";
          double_puppet_server_map = {};
          login_shared_secret_map = {};
          command_prefix = "!wa";
          permissions."*" = "relay";
          relay = {
            enabled = true;
          };
        };
        logging = {
          min_level = "info";
          writers = [
            {
              type = "stdout";
              format = "pretty-colored";
            }
            {
              type = "file";
              format = "json";
            }
          ];
        };
      };
      example = {
        settings = {
          homeserver.address = "https://matrix.myhomeserver.org";
          appservice.database = {
            type = "postgres";
            uri = "postgresql:///mautrix_whatsapp?host=/run/postgresql";
          };
          bridge.permissions = {
            "@admin:myhomeserver.org" = "admin";
          };
        };
      };
      description = lib.mdDoc ''
        {file}`config.yaml` configuration as a Nix attribute set.
        Configuration options should match those described in
        [example-config.yaml](https://github.com/mautrix/whatsapp/blob/master/example-config.yaml).

        Secret tokens should be specified using {option}`environmentFile`
        instead of this world-readable attribute set.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = lib.mdDoc ''
        File containing environment variables to be passed to the mautrix-whatsapp service,
        in which secret tokens can be specified securely by optionally defining a value for
        `MAUTRIX_WHATSAPP_BRIDGE_LOGIN_SHARED_SECRET`.
      '';
    };

    serviceDependencies = mkOption {
      type = with types; listOf str;
      default = optional config.services.matrix-synapse.enable "matrix-synapse.service";
      defaultText = literalExpression ''
        optional config.services.matrix-synapse.enable "matrix-synapse.service"
      '';
      description = lib.mdDoc ''
        List of Systemd services to require and wait for when starting the application service.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.mautrix-whatsapp = {
      description = "Mautrix-WhatsApp Service - A WhatsApp bridge for Matrix";

      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"] ++ cfg.serviceDependencies;
      after = ["network-online.target"] ++ cfg.serviceDependencies;

      preStart = ''
        # substitute the settings file by environment variables
        # in this case read from EnvironmentFile
        test -f '${settingsFile}' && rm -f '${settingsFile}'
        old_umask=$(umask)
        umask 0177
        ${pkgs.envsubst}/bin/envsubst \
          -o '${settingsFile}' \
          -i '${settingsFileUnsubstituted}'
        umask $old_umask

        # generate the appservice's registration file if absent
        if [ ! -f '${registrationFile}' ]; then
          ${pkgs.mautrix-whatsapp}/bin/mautrix-whatsapp \
            --generate-registration \
            --config='${settingsFile}' \
            --registration='${registrationFile}'
        fi
        chmod 640 ${registrationFile}

        umask 0177
        ${pkgs.yq}/bin/yq -s '.[0].appservice.as_token = .[1].as_token
          | .[0].appservice.hs_token = .[1].hs_token
          | .[0]' '${settingsFile}' '${registrationFile}' \
          > '${settingsFile}.tmp'
        mv '${settingsFile}.tmp' '${settingsFile}'
        umask $old_umask
      '';

      serviceConfig = {
        DynamicUser = true;
        EnvironmentFile = cfg.environmentFile;
        StateDirectory = baseNameOf dataDir;
        WorkingDirectory = "${dataDir}";
        ExecStart = ''
          ${pkgs.mautrix-whatsapp}/bin/mautrix-whatsapp \
          --config='${settingsFile}' \
          --registration='${registrationFile}'
        '';
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = "30s";
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = ["@system-service"];
        Type = "simple";
        UMask = 0027;
      };
      restartTriggers = [settingsFileUnsubstituted];
    };
  };
}
