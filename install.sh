#!/bin/bash

# --- Configuração Inicial e Cores ---
GREEN1='\033[38;2;0;255;0m' # Verde Lima
GREEN2='\033[38;2;0;220;0m'
GREEN3='\033[38;2;0;190;0m'
GREEN4='\033[38;2;0;160;0m'
GREEN5='\033[38;2;0;130;0m'
GREEN6='\033[38;2;0;100;0m'
NC='\033[0m' # Sem Cor
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'

# --- Variáveis Globais (Serão definidas interativamente) ---
MINECRAFT_VERSION=""
SERVER_TYPE=""
BUILD_NUMBER="latest"
MODLOADER_INSTALLER_VERSION=""
MODLOADER_SERVER_FILE="run.sh"
SERVER_MEMORY=${SERVER_MEMORY:-2048}

DEFAULT_SERVER_JAR_NAME="server.jar"
TARGET_SERVER_FILE="$DEFAULT_SERVER_JAR_NAME"

# --- Funções Auxiliares ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }
log_prompt() { echo -ne "${CYAN}[INPUT]${NC} $1"; }

ensure_dependencies() {
    log_info "Verificando dependências necessárias (curl, jq, java)..."
    local missing_any=0
    local deps_to_install_list=() # Array para nomes de pacotes

    # Verificar curl
    if ! command -v curl &> /dev/null; then
        log_warning "'curl' não encontrado."
        deps_to_install_list+=("curl")
        missing_any=1
    else
        log_info "'curl' encontrado: $(curl --version | head -n 1)"
    fi

    # Verificar jq
    if ! command -v jq &> /dev/null; then
        log_warning "'jq' não encontrado."
        deps_to_install_list+=("jq")
        missing_any=1
    else
        log_info "'jq' encontrado: $(jq --version)"
    fi

    # Verificar java
    if ! command -v java &> /dev/null; then
        log_warning "'java' não encontrado."
        # Adicionaremos um nome de pacote genérico para Java que será ajustado pelo gerenciador
        deps_to_install_list+=("java_placeholder") # Será substituído por openjdk-17-jre-headless ou similar
        missing_any=1
    else
        DETECTED_JAVA_VERSION_INFO_DEP=$(java -version 2>&1 | grep -E 'version ".*?"' | head -n 1 | sed -E 's/.*version "(.*?)".*/\1/')
        log_info "'java' encontrado: Versão ${DETECTED_JAVA_VERSION_INFO_DEP}"
    fi

    if [ "$missing_any" -eq 1 ]; then
        log_warning "Algumas dependências estão faltando."
        # Constrói a string de nomes para o usuário
        local pretty_deps_list=""
        for dep_name in "${deps_to_install_list[@]}"; do
            if [[ "$dep_name" == "java_placeholder" ]]; then
                pretty_deps_list+="Java (OpenJDK 17 JRE Headless) "
            else
                pretty_deps_list+="$dep_name "
            fi
        done

        log_prompt "O script tentará instalar: ${pretty_deps_list}. Isso requer privilégios de superusuário (sudo) e pode solicitar sua senha. Continuar? (s/N): "
        read -r install_confirm
        if [[ "$install_confirm" != "s" && "$install_confirm" != "S" ]]; then
            log_error "Instalação de dependências cancelada pelo usuário. O script não pode prosseguir."
        fi

        # Detectar gerenciador de pacotes e instalar
        # Tentaremos usar sudo. Se o usuário não tiver permissão, o comando sudo falhará.
        if command -v apt-get &> /dev/null; then # Debian, Ubuntu, Mint
            log_info "Usando 'apt-get' para instalar dependências..."
            sudo apt-get update -y
            for dep_item in "${deps_to_install_list[@]}"; do
                if [[ "$dep_item" == "java_placeholder" ]]; then
                    sudo apt-get install -y openjdk-17-jre-headless || log_error "Falha ao instalar openjdk-17-jre-headless com apt-get."
                else
                    sudo apt-get install -y "$dep_item" || log_error "Falha ao instalar $dep_item com apt-get."
                fi
            done
        elif command -v dnf &> /dev/null; then # Fedora, RHEL (newer), CentOS (newer)
            log_info "Usando 'dnf' para instalar dependências..."
            for dep_item in "${deps_to_install_list[@]}"; do
                if [[ "$dep_item" == "java_placeholder" ]]; then
                    sudo dnf install -y java-17-openjdk-headless || log_error "Falha ao instalar java-17-openjdk-headless com dnf."
                else
                    sudo dnf install -y "$dep_item" || log_error "Falha ao instalar $dep_item com dnf."
                fi
            done
        elif command -v yum &> /dev/null; then # RHEL (older), CentOS (older)
            log_info "Usando 'yum' para instalar dependências..."
             for dep_item in "${deps_to_install_list[@]}"; do
                if [[ "$dep_item" == "java_placeholder" ]]; then
                    sudo yum install -y java-17-openjdk-headless || log_error "Falha ao instalar java-17-openjdk-headless com yum."
                else
                    sudo yum install -y "$dep_item" || log_error "Falha ao instalar $dep_item com yum."
                fi
            done
        elif command -v apk &> /dev/null; then # Alpine
            log_info "Usando 'apk' para instalar dependências..." # sudo geralmente não é usado/necessário se root no Alpine
            apk update
            for dep_item in "${deps_to_install_list[@]}"; do
                if [[ "$dep_item" == "java_placeholder" ]]; then
                    apk add openjdk17-jre-headless || log_error "Falha ao instalar openjdk17-jre-headless com apk."
                else
                    apk add "$dep_item" || log_error "Falha ao instalar $dep_item com apk."
                fi
            done
        elif command -v pacman &> /dev/null; then # Arch
            log_info "Usando 'pacman' para instalar dependências..."
            for dep_item in "${deps_to_install_list[@]}"; do
                if [[ "$dep_item" == "java_placeholder" ]]; then
                    sudo pacman -S --noconfirm --needed jre-openjdk-headless || log_error "Falha ao instalar jre-openjdk-headless com pacman."
                else
                    sudo pacman -S --noconfirm --needed "$dep_item" || log_error "Falha ao instalar $dep_item com pacman."
                fi
            done
        else
            log_error "Gerenciador de pacotes não reconhecido ou não suportado por este script. Por favor, instale manualmente: $pretty_deps_list"
        fi

        # Re-verificar após tentativa de instalação
        log_info "Re-verificando dependências..."
        if ! command -v curl &> /dev/null; then log_error "'curl' ainda não está instalado após a tentativa. Verifique os erros acima."; fi
        if ! command -v jq &> /dev/null; then log_error "'jq' ainda não está instalado após a tentativa. Verifique os erros acima."; fi
        if ! command -v java &> /dev/null; then log_error "'java' ainda não está instalado após a tentativa. Verifique os erros acima."; fi
        log_info "Dependências parecem ter sido instaladas com sucesso!"
    else
        log_info "Todas as dependências necessárias já estão presentes."
    fi
    echo # Linha em branco para formatação
}


download_file() {
    local url="$1"
    local output_name="$2"
    log_info "Baixando '$output_name' de '$url'..."
    curl -sSL -o "$output_name" "$url"
    if [ $? -ne 0 ] || [ ! -f "$output_name" ] || [ $(stat -c%s "$output_name") -lt 10000 ]; then # Checagem básica de tamanho
        log_error "Falha no download de '$output_name' ou arquivo muito pequeno/corrompido."
    fi
    log_info "Download de '$output_name' concluído."
}

# --- Lógica Interativa Principal ---

clear
echo -e "${GREEN1}K${GREEN2}e${GREEN3}y${GREEN4} ${GREEN5}H${GREEN6}o${GREEN1}s${GREEN2}t${NC} - Instalador Interativo de Servidor Minecraft"
echo -e "${BLUE}================================================================${NC}"

# Chama a função de verificação e instalação de dependências AQUI
ensure_dependencies

echo # Linha em branco para formatação

# 1. Escolha do Tipo de Servidor
PS3=$(echo -e "${CYAN}Escolha o tipo de servidor:${NC} ")
server_options=("Vanilla" "PaperMC" "Spigot" "Bukkit" "Forge" "NeoForge" "Sair")
select opt_server_type in "${server_options[@]}"; do
    case $opt_server_type in
        "Vanilla") SERVER_TYPE="vanilla"; break;;
        "PaperMC") SERVER_TYPE="paper"; break;;
        "Spigot") SERVER_TYPE="spigot"; break;;
        "Bukkit") SERVER_TYPE="bukkit"; break;;
        "Forge") SERVER_TYPE="forge"; break;;
        "NeoForge") SERVER_TYPE="neoforge"; break;;
        "Sair") echo "Instalação cancelada."; exit 0;;
        *) echo "Opção inválida $REPLY";;
    esac
done
log_info "Tipo de Servidor Selecionado: $SERVER_TYPE"
echo

# 2. Escolha da Versão do Minecraft (dependendo do tipo)
case $SERVER_TYPE in
    "vanilla" | "paper")
        log_info "Buscando versões disponíveis para $SERVER_TYPE..."
        versions_array=()
        if [ "$SERVER_TYPE" == "vanilla" ]; then
            MANIFEST_URL=$(curl -sSL https://launchermeta.mojang.com/mc/game/version_manifest.json)
            if [[ -z "$MANIFEST_URL" ]]; then log_error "Não foi possível obter o manifesto de versões da Mojang."; fi
            # Filtra apenas releases e ordena (mais recentes primeiro - `reverse` no final se `jq` suportar, ou `tac` depois)
            mapfile -t versions_array < <(echo "$MANIFEST_URL" | jq -r '.versions[] | select(.type == "release") | .id' | sort -V -r)
        elif [ "$SERVER_TYPE" == "paper" ]; then
            PROJECT_DATA_JSON=$(curl -sSL "https://api.papermc.io/v2/projects/paper")
            if [[ -z "$PROJECT_DATA_JSON" ]]; then log_error "Não foi possível obter dados do projeto PaperMC."; fi
            # As versões já vêm em ordem (mais antigas primeiro), então usamos `reverse` se quisermos as mais novas primeiro no `select`
            mapfile -t versions_array < <(echo "$PROJECT_DATA_JSON" | jq -r '.versions[]' | sort -V -r)
            versions_array=("latest" "${versions_array[@]}") # Adiciona "latest" como primeira opção
        fi

        if [ ${#versions_array[@]} -eq 0 ]; then
            log_error "Nenhuma versão encontrada para $SERVER_TYPE. Verifique sua conexão ou a API do provedor."
        fi

        echo "Versões disponíveis para $SERVER_TYPE (as mais recentes no topo/início):"
        PS3=$(echo -e "${CYAN}Escolha a versão do Minecraft (ou digite o número):${NC} ")
        select mc_version_opt in "${versions_array[@]}"; do
            if [[ -n "$mc_version_opt" ]]; then
                MINECRAFT_VERSION=$mc_version_opt
                break
            else
                echo "Opção inválida '$REPLY'. Tente novamente."
            fi
        done
        ;;

    "spigot" | "bukkit")
        log_warning "Para $SERVER_TYPE, você precisará digitar a versão do Minecraft (ex: 1.16.5, 1.20.4)."
        log_warning "Downloads diretos para Spigot/Bukkit podem não ser confiáveis; BuildTools é o método oficial."
        while [[ -z "$MINECRAFT_VERSION" ]]; do
            log_prompt "Digite a versão do Minecraft para $SERVER_TYPE: "
            read MINECRAFT_VERSION
            if [[ -z "$MINECRAFT_VERSION" ]]; then
                log_warning "A versão não pode ser vazia."
            fi
        done
        ;;

    "forge" | "neoforge")
        log_info "Para $SERVER_TYPE, precisaremos da versão do Minecraft e da versão do instalador do Modloader."
        while [[ -z "$MINECRAFT_VERSION" ]]; do
            log_prompt "Digite a versão do Minecraft (ex: 1.12.2, 1.20.1): "
            read MINECRAFT_VERSION
             if [[ -z "$MINECRAFT_VERSION" ]]; then log_warning "A versão do Minecraft não pode ser vazia."; fi
        done
        
        log_prompt "Digite a versão do instalador do $SERVER_TYPE (ex para Forge 1.20.1: 47.2.20; ex para NeoForge 1.20.4: 20.4.227-beta): "
        read MODLOADER_INSTALLER_VERSION
        # Validação básica, poderia ser mais robusta
        if [[ -z "$MODLOADER_INSTALLER_VERSION" ]]; then log_error "A versão do instalador do Modloader é obrigatória para $SERVER_TYPE."; fi

        log_prompt "Digite o nome do arquivo principal do servidor (ex: run.sh, forge.jar, ou deixe em branco para '${MODLOADER_SERVER_FILE}'): "
        read user_modloader_file
        if [[ -n "$user_modloader_file" ]]; then
            MODLOADER_SERVER_FILE="$user_modloader_file"
        fi
        ;;
esac
log_info "Versão do Minecraft Selecionada: $MINECRAFT_VERSION"
[ -n "$MODLOADER_INSTALLER_VERSION" ] && log_info "Versão do Instalador $SERVER_TYPE: $MODLOADER_INSTALLER_VERSION"
[ "$SERVER_TYPE" == "forge" ] || [ "$SERVER_TYPE" == "neoforge" ] && log_info "Arquivo Principal $SERVER_TYPE: $MODLOADER_SERVER_FILE"
echo

# --- Confirmação Final ---
log_prompt "Você deseja instalar $SERVER_TYPE $MINECRAFT_VERSION com as configurações acima? (s/N): "
read confirmation
if [[ "$confirmation" != "s" && "$confirmation" != "S" ]]; then
    echo "Instalação cancelada pelo usuário."
    exit 0
fi
echo

# --- Lógica de Instalação (Adaptada do script não interativo) ---
log_info "Iniciando o processo de instalação..."
ACTUAL_MINECRAFT_VERSION="$MINECRAFT_VERSION" # Para uso interno, especialmente se "latest" foi selecionado para Paper

case "$SERVER_TYPE" in
    "vanilla")
        log_info "Instalando Minecraft Vanilla $ACTUAL_MINECRAFT_VERSION..."
        MANIFEST_URL_DL=$(curl -sSL https://launchermeta.mojang.com/mc/game/version_manifest.json)
        VERSION_URL_DL=$(echo "${MANIFEST_URL_DL}" | jq -r --arg VERSION "${ACTUAL_MINECRAFT_VERSION}" '.versions[] | select(.id == $VERSION) | .url')
        if [[ -z "$VERSION_URL_DL" || "$VERSION_URL_DL" == "null" ]]; then log_error "URL da versão Vanilla '${ACTUAL_MINECRAFT_VERSION}' não encontrada."; fi
        SERVER_DOWNLOAD_URL_DL=$(curl -sSL "${VERSION_URL_DL}" | jq -r '.downloads.server.url')
        if [[ -z "$SERVER_DOWNLOAD_URL_DL" || "$SERVER_DOWNLOAD_URL_DL" == "null" ]]; then log_error "URL de download do servidor Vanilla '${ACTUAL_MINECRAFT_VERSION}' não encontrada."; fi
        download_file "$SERVER_DOWNLOAD_URL_DL" "$DEFAULT_SERVER_JAR_NAME"
        TARGET_SERVER_FILE="$DEFAULT_SERVER_JAR_NAME"
        ;;

    "paper")
        log_info "Instalando PaperMC..."
        USER_REQUESTED_MINECRAFT_VERSION_FOR_PAPER="$MINECRAFT_VERSION"

        if [[ "$ACTUAL_MINECRAFT_VERSION" == "latest" ]]; then
            log_info "MINECRAFT_VERSION é 'latest'. Tentando descobrir a última versão do Minecraft suportada pelo PaperMC..."
            PROJECT_DATA_JSON_DL=$(curl -sSL "https://api.papermc.io/v2/projects/paper")
            if [ $? -ne 0 ] || [[ -z "$PROJECT_DATA_JSON_DL" ]]; then log_error "Falha ao obter dados do projeto PaperMC da API."; fi
            if echo "$PROJECT_DATA_JSON_DL" | jq -e '.error' > /dev/null; then log_error "Erro da API ao obter dados do projeto PaperMC: $(echo "$PROJECT_DATA_JSON_DL" | jq -r .error)."; fi
            ACTUAL_MINECRAFT_VERSION=$(echo "$PROJECT_DATA_JSON_DL" | jq -r '.versions[-1] // empty')
            if [[ -z "$ACTUAL_MINECRAFT_VERSION" ]]; then log_error "Não foi possível determinar a última versão do Minecraft para PaperMC. Resposta: $PROJECT_DATA_JSON_DL"; fi
            log_info "Última versão do Minecraft para PaperMC detectada pela API: $ACTUAL_MINECRAFT_VERSION"
        fi

        API_VERSION_URL_DL="https://api.papermc.io/v2/projects/paper/versions/${ACTUAL_MINECRAFT_VERSION}"
        CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL="$BUILD_NUMBER"
        
        if [[ "$CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL" == "latest" ]]; then
            log_info "Buscando o último build para PaperMC ${ACTUAL_MINECRAFT_VERSION}..."
            BUILDS_DATA_JSON_DL=$(curl -sSL "${API_VERSION_URL_DL}/builds")
            if [ $? -ne 0 ] || [[ -z "$BUILDS_DATA_JSON_DL" ]]; then log_error "Falha ao obter dados de builds para PaperMC ${ACTUAL_MINECRAFT_VERSION}."; fi
            if echo "$BUILDS_DATA_JSON_DL" | jq -e '.error' > /dev/null; then log_error "Erro da API ao obter builds para PaperMC ${ACTUAL_MINECRAFT_VERSION}: $(echo "$BUILDS_DATA_JSON_DL" | jq -r .error)."; fi
            CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL=$(echo "$BUILDS_DATA_JSON_DL" | jq -r '.builds[-1].build // empty')
            if [[ -z "$CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL" ]]; then log_error "Não foi possível obter o último número de build para PaperMC ${ACTUAL_MINECRAFT_VERSION}."; fi
            log_info "  Último build encontrado para Paper ${ACTUAL_MINECRAFT_VERSION}: ${CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL}"
        fi
        
        DOWNLOAD_URL_DL="${API_VERSION_URL_DL}/builds/${CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL}/downloads/paper-${ACTUAL_MINECRAFT_VERSION}-${CURRENT_BUILD_NUMBER_TO_DOWNLOAD_DL}.jar"
        download_file "$DOWNLOAD_URL_DL" "$DEFAULT_SERVER_JAR_NAME"
        TARGET_SERVER_FILE="$DEFAULT_SERVER_JAR_NAME"
        
        if [[ "$USER_REQUESTED_MINECRAFT_VERSION_FOR_PAPER" == "latest" ]]; then
            MINECRAFT_VERSION="$ACTUAL_MINECRAFT_VERSION" 
        fi
        ;;

    "spigot" | "bukkit")
        FLAVOR_NAME=$SERVER_TYPE
        if [ "$SERVER_TYPE" == "bukkit" ]; then FLAVOR_NAME="craftbukkit"; fi
        log_info "Tentando baixar $SERVER_TYPE $ACTUAL_MINECRAFT_VERSION de cdn.getbukkit.org..."
        # Tentar com sufixo .jar e sem, algumas versões no GetBukkit não tem .jar no nome do link
        DL_URL_WITH_SUFFIX="https://cdn.getbukkit.org/${FLAVOR_NAME}/${FLAVOR_NAME}-${ACTUAL_MINECRAFT_VERSION}.jar"
        DL_URL_NO_SUFFIX="https://cdn.getbukkit.org/${FLAVOR_NAME}/${FLAVOR_NAME}-${ACTUAL_MINECRAFT_VERSION}"

        curl -sSL -f -o "$DEFAULT_SERVER_JAR_NAME" "$DL_URL_WITH_SUFFIX"
        if [ $? -ne 0 ] || [ ! -f "$DEFAULT_SERVER_JAR_NAME" ] || [ $(stat -c%s "$DEFAULT_SERVER_JAR_NAME") -lt 100000 ]; then
            log_warning "Falha ao baixar de $DL_URL_WITH_SUFFIX ou arquivo pequeno. Tentando sem sufixo .jar no URL..."
            rm -f "$DEFAULT_SERVER_JAR_NAME" 
            curl -sSL -f -o "$DEFAULT_SERVER_JAR_NAME" "$DL_URL_NO_SUFFIX"
            if [ $? -ne 0 ] || [ ! -f "$DEFAULT_SERVER_JAR_NAME" ] || [ $(stat -c%s "$DEFAULT_SERVER_JAR_NAME") -lt 100000 ]; then
                 log_error "Falha ao baixar $SERVER_TYPE. Verifique a versão e a disponibilidade em GetBukkit, ou use BuildTools."
            fi
        fi
        log_info "Download de $SERVER_TYPE $ACTUAL_MINECRAFT_VERSION (de GetBukkit) concluído."
        TARGET_SERVER_FILE="$DEFAULT_SERVER_JAR_NAME"
        ;;

    "forge")
        log_info "Instalando Forge $ACTUAL_MINECRAFT_VERSION (Instalador: $MODLOADER_INSTALLER_VERSION)..."
        MC_PRIMARY_VERSION_DL=$(echo "$ACTUAL_MINECRAFT_VERSION" | cut -d. -f1)
        MC_SECONDARY_VERSION_DL=$(echo "$ACTUAL_MINECRAFT_VERSION" | cut -d. -f2)
        FORGE_MAVEN_URL_DL="https://maven.minecraftforge.net/net/minecraftforge/forge"
        if [[ "$MC_PRIMARY_VERSION_DL" -eq 1 && "$MC_SECONDARY_VERSION_DL" -lt 17 ]]; then
             FORGE_MAVEN_URL_DL="http://files.minecraftforge.net/maven/net/minecraftforge/forge"
        fi
        FORGE_INSTALLER_URL_DL="${FORGE_MAVEN_URL_DL}/${ACTUAL_MINECRAFT_VERSION}-${MODLOADER_INSTALLER_VERSION}/forge-${ACTUAL_MINECRAFT_VERSION}-${MODLOADER_INSTALLER_VERSION}-installer.jar"
        download_file "$FORGE_INSTALLER_URL_DL" "forge_installer.jar"
        java -jar forge_installer.jar --installServer
        if [ $? -ne 0 ]; then log_error "Instalador do Forge falhou."; fi
        rm -f forge_installer.jar
        TARGET_SERVER_FILE="$MODLOADER_SERVER_FILE" # Usa o que o usuário definiu ou o padrão "run.sh"
        if [[ ! -f "$TARGET_SERVER_FILE" ]]; then
            # Tenta ser um pouco mais inteligente se o arquivo especificado não existir
            if [[ "$MODLOADER_SERVER_FILE" == *.jar && -f "minecraft_server.${ACTUAL_MINECRAFT_VERSION}.jar" ]]; then
                log_warning "Arquivo '$MODLOADER_SERVER_FILE' não encontrado, mas 'minecraft_server.${ACTUAL_MINECRAFT_VERSION}.jar' existe. Renomeando..."
                mv "minecraft_server.${ACTUAL_MINECRAFT_VERSION}.jar" "$MODLOADER_SERVER_FILE"
                TARGET_SERVER_FILE="$MODLOADER_SERVER_FILE"
            elif [[ -f "run.sh" ]]; then
                 log_warning "Arquivo '$MODLOADER_SERVER_FILE' não encontrado. Usando 'run.sh' detectado."
                 TARGET_SERVER_FILE="run.sh"
            else
                log_warning "Arquivo principal Forge '$MODLOADER_SERVER_FILE' não encontrado após a instalação. Verifique o nome ou a saída do instalador."
            fi
        fi
        if [[ "$TARGET_SERVER_FILE" == *.sh ]]; then chmod +x "$TARGET_SERVER_FILE"; fi
        ;;

    "neoforge")
        log_info "Instalando NeoForge $ACTUAL_MINECRAFT_VERSION (Instalador: $MODLOADER_INSTALLER_VERSION)..."
        NEOFORGE_INSTALLER_URL_DL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${MODLOADER_INSTALLER_VERSION}/neoforge-${MODLOADER_INSTALLER_VERSION}-installer.jar"
        download_file "$NEOFORGE_INSTALLER_URL_DL" "neoforge_installer.jar"
        java -jar neoforge_installer.jar --installServer
        if [ $? -ne 0 ]; then log_error "Instalador do NeoForge falhou."; fi
        rm -f neoforge_installer.jar
        TARGET_SERVER_FILE="$MODLOADER_SERVER_FILE"
        if [[ ! -f "$TARGET_SERVER_FILE" ]]; then
             if [[ -f "run.sh" ]]; then # NeoForge tipicamente cria run.sh e run.bat
                log_warning "Arquivo '$MODLOADER_SERVER_FILE' não encontrado. Usando 'run.sh' detectado."
                TARGET_SERVER_FILE="run.sh"
            else
                log_warning "Arquivo principal NeoForge '$MODLOADER_SERVER_FILE' não encontrado após a instalação. Verifique o nome ou a saída do instalador."
            fi
        fi
        if [[ "$TARGET_SERVER_FILE" == *.sh ]]; then chmod +x "$TARGET_SERVER_FILE"; fi
        ;;
    *)
        log_error "Tipo de servidor desconhecido: $SERVER_TYPE" ;;
esac

# --- Aceitar EULA ---
log_info "Aceitando EULA do Minecraft..."
echo "eula=true" > eula.txt

# --- Criar o script de inicialização `start.sh` ---
log_info "Criando script de inicialização 'start.sh'..."
# Tenta obter a versão do Java novamente, caso tenha sido instalada agora
DETECTED_JAVA_VERSION_INFO_START=$(java -version 2>&1 | grep -E 'version ".*?"' | head -n 1 | sed -E 's/.*version "(.*?)".*/\1/')

cat > start.sh <<EOF
#!/bin/bash
# Script de inicialização para o servidor Minecraft - Gerado por install_interactive.sh

echo -e "${GREEN1}K${GREEN2}e${GREEN3}y${GREEN4} ${GREEN5}H${GREEN6}o${GREEN1}s${GREEN2}t${NC} - Iniciando Servidor..."
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}[INFO]${NC} Tipo de Servidor: ${SERVER_TYPE}"
echo -e "${BLUE}[INFO]${NC} Versão Minecraft: ${MINECRAFT_VERSION}"
echo -e "${BLUE}[INFO]${NC} Memória Alocada: ${SERVER_MEMORY}M"
echo -e "${BLUE}[INFO]${NC} Java Version: ${DETECTED_JAVA_VERSION_INFO_START:-"Não detectado"}"
echo -e "${BLUE}[INFO]${NC} Arquivo Principal: ${TARGET_SERVER_FILE}"
echo -e "${BLUE}================================================================${NC}"

if [[ "${TARGET_SERVER_FILE}" == *.sh ]]; then
    # Adiciona Aikar's flags se não for Forge/NeoForge (que podem ter seus próprios scripts otimizados)
    # Ou se for um script customizado que não seja o run.sh padrão do modloader
    # Esta é uma heurística e pode precisar de ajuste
    if [[ "$SERVER_TYPE" != "forge" && "$SERVER_TYPE" != "neoforge" ]] || [[ "$TARGET_SERVER_FILE" != "run.sh" ]]; then
        log_warning "Executando script .sh. Certifique-se que ele utiliza a memória (${SERVER_MEMORY}M) e flags Java otimizadas."
    fi
    exec ./"${TARGET_SERVER_FILE}" "\$@"
elif [[ "${TARGET_SERVER_FILE}" == *.jar ]]; then
    # Usando as flags de Aikar para melhor performance (comuns para Paper/Spigot/Vanilla)
    # Fonte: https://aikar.co/2018/07/02/tuning-the-jvm-g1gc-garbage-collector-flags-for-minecraft/
    # Estas flags são para G1GC, que é o padrão em Java 9+. OpenJDK 17 usa G1GC.
    echo -e "${BLUE}[INFO]${NC} Usando flags de otimização G1GC para inicialização do JAR."
    exec java -Xms${SERVER_MEMORY}M -Xmx${SERVER_MEMORY}M \
        -XX:+UseG1GC \
        -XX:+ParallelRefProcEnabled \
        -XX:MaxGCPauseMillis=200 \
        -XX:+UnlockExperimentalVMOptions \
        -XX:+DisableExplicitGC \
        -XX:+AlwaysPreTouch \
        -XX:G1NewSizePercent=30 \
        -XX:G1MaxNewSizePercent=40 \
        -XX:G1HeapRegionSize=8M \
        -XX:G1ReservePercent=20 \
        -XX:G1HeapWastePercent=5 \
        -XX:G1MixedGCCountTarget=4 \
        -XX:InitiatingHeapOccupancyPercent=15 \
        -XX:G1MixedGCLiveThresholdPercent=90 \
        -XX:G1RSetUpdatingPauseTimePercent=5 \
        -XX:SurvivorRatio=32 \
        -XX:+PerfDisableSharedMem \
        -XX:MaxTenuringThreshold=1 \
        -Dusing.aikars.flags=https://mcflags.emc.gs \
        -Daikars.new.flags=true \
        -Dterminal.jline=false -Dterminal.ansi=true \
        -jar "${TARGET_SERVER_FILE}" nogui "\$@"
else
    echo -e "${RED}[ERRO FATAL]${NC} O arquivo principal do servidor ('${TARGET_SERVER_FILE}') não é um .sh nem .jar, ou não foi encontrado."
    exit 1
fi
EOF
chmod +x start.sh

log_info "Script 'start.sh' criado com sucesso."
echo -e "${GREEN1}================================================================${NC}"
log_info "Instalação do servidor Minecraft (${SERVER_TYPE} - ${MINECRAFT_VERSION}) concluída!"
echo -e "Para iniciar o servidor (neste diretório), execute: ./start.sh"
echo -e "${GREEN1}================================================================${NC}"

exit 0