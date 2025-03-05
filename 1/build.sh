#!/bin/bash

# Очистка старых артефактов (кроме jdk, чтобы не удалить его до использования)
echo "Cleaning up old artifacts..."
rm -rf dist jre jdk.tar.gz Demo.tar.gz

# Определение архитектуры системы
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    JDK_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
elif [ "$ARCH" = "aarch64" ]; then
    JDK_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/aarch64/jdk/hotspot/normal/eclipse"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Проверка, существует ли JDK, и загрузка, если его нет
if [ ! -d "jdk" ]; then
    echo "Downloading JDK 21 for $ARCH..."
    curl -L -o jdk.tar.gz "$JDK_URL"
    if [ $? -ne 0 ]; then
        echo "Failed to download JDK!"
        exit 1
    fi

    echo "Extracting JDK..."
    tar -xzf jdk.tar.gz

    # Проверяем, какая папка создалась после распаковки (безопасная проверка)
    JDK_DIR=$(find . -maxdepth 1 -type d -name "jdk-21*" | head -n 1)
    if [ -n "$JDK_DIR" ]; then
        mv "$JDK_DIR" jdk
    else
        echo "JDK directory not found after extraction!"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to extract JDK!"
        exit 1
    fi
else
    echo "JDK already exists, skipping download."
fi

# Установка JAVA_HOME
export JAVA_HOME=/home/lisa/IdeaProjects/Demo/jdk
export PATH=$JAVA_HOME/bin:$PATH

# Проверка JAVA_HOME
if [ ! -f "$JAVA_HOME/bin/java" ]; then
    echo "JAVA_HOME is not set correctly: $JAVA_HOME does not contain a valid JDK!"
    exit 1
fi
if [ ! -f "$JAVA_HOME/bin/javac" ]; then
    echo "JAVA_HOME does not point to a JDK (javac not found)!"
    exit 1
fi

# Сборка проекта с Maven
echo "Building project with Maven..."
mvn clean package
if [ $? -ne 0 ]; then
    echo "Maven build failed!"
    exit 1
fi

# Проверка, существует ли JAR-файл
if [ ! -f "target/Demo-1.0-SNAPSHOT.jar" ]; then
    echo "JAR file target/Demo-1.0-SNAPSHOT.jar not found!"
    exit 1
fi

# Определение необходимых модулей с помощью jdeps
echo "Determining required modules with jdeps..."
MODULES=$($JAVA_HOME/bin/jdeps --multi-release 21 --ignore-missing-deps --print-module-deps target/Demo-1.0-SNAPSHOT.jar 2>&1)
if [ $? -ne 0 ]; then
    echo "jdeps failed with output: $MODULES"
    # Если jdeps не может определить модули, используем java.base по умолчанию
    MODULES="java.base"
    echo "Falling back to default modules: $MODULES"
fi
echo "Required modules: $MODULES"

# Убедимся, что директория jre/ не существует перед созданием JRE
if [ -d "jre" ]; then
    echo "Removing existing jre/ directory..."
    rm -rf jre
    if [ $? -ne 0 ]; then
        echo "Failed to remove existing jre/ directory!"
        exit 1
    fi
fi

# Создание JRE с jlink
echo "Creating JRE with jlink..."
$JAVA_HOME/bin/jlink --add-modules "$MODULES" --output jre --compress=zip-6 --no-header-files --no-man-pages
if [ $? -ne 0 ]; then
    echo "jlink failed!"
    exit 1
fi

# Проверка созданной JRE
echo "Testing JRE by running the JAR file..."
./jre/bin/java -jar target/Demo-1.0-SNAPSHOT.jar
if [ $? -ne 0 ]; then
    echo "Failed to run JAR with created JRE!"
    exit 1
fi

# Создание исполняемого файла и .deb пакета с jpackage
echo "Creating executable and .deb package with jpackage..."
$JAVA_HOME/bin/jpackage --input target --name Demo --main-jar Demo-1.0-SNAPSHOT.jar --main-class com.example.Main --type deb --dest dist --runtime-image jre --app-version 1.0-SNAPSHOT --verbose
if [ $? -ne 0 ]; then
    echo "jpackage failed!"
    exit 1
fi

# Переименование .deb файла для соответствия ожидаемому имени
if [ -f "dist/demo_1.0-SNAPSHOT_amd64.deb" ]; then
    echo "Renaming .deb package to match expected name..."
    mv dist/demo_1.0-SNAPSHOT_amd64.deb dist/Demo-1.0-SNAPSHOT.deb
    if [ $? -ne 0 ]; then
        echo "Failed to rename .deb package!"
        exit 1
    fi
else
    echo "Expected .deb package not found!"
    exit 1
fi

# Извлечение dist/Demo из .deb пакета
echo "Extracting dist/Demo from .deb package..."
mkdir -p dist/deb_contents
dpkg-deb -x dist/Demo-1.0-SNAPSHOT.deb dist/deb_contents
if [ $? -ne 0 ]; then
    echo "Failed to extract .deb package!"
    exit 1
fi
if [ -f "dist/deb_contents/opt/demo/bin/Demo" ]; then
    mv dist/deb_contents/opt/demo/bin/Demo dist/
    chmod +x dist/Demo
    echo "dist/Demo extracted successfully."
else
    echo "dist/Demo not found in .deb package."
    exit 1
fi
rm -rf dist/deb_contents

# Копирование зависимостей в dist/libs
if [ -d "target/libs" ]; then
    echo "Copying dependencies to dist/libs..."
    mkdir -p dist/libs
    cp target/libs/*.jar dist/libs/
    if [ $? -ne 0 ]; then
        echo "Failed to copy dependencies!"
        exit 1
    fi
else
    echo "Dependencies directory target/libs not found!"
    echo "Please check if maven-dependency-plugin is correctly configured in pom.xml."
    exit 1
fi

# Создание архива
echo "Creating archive Demo.tar.gz..."
tar -czf Demo.tar.gz dist
if [ $? -ne 0 ]; then
    echo "Failed to create archive!"
    exit 1
fi

echo "Build completed successfully!"