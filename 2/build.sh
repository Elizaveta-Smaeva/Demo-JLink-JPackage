#!/bin/bash

# Очистка старых артефактов
echo "Cleaning up old artifacts..."
rm -rf dist target

# Установка JAVA_HOME
export JAVA_HOME=/home/lisa/.jdks/openjdk-21.0.1
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

# Проверка, существует ли .deb пакет
if [ -f "target/dist/Demo_1.0.deb" ]; then
    echo "Renaming .deb package to match expected name..."
    mv target/dist/Demo_1.0.deb target/dist/Demo-1.0-SNAPSHOT.deb
    if [ $? -ne 0 ]; then
        echo "Failed to rename .deb package!"
        exit 1
    fi
else
    echo "Expected .deb package not found! Available files in target/dist:"
    ls -l target/dist/
    exit 1
fi

# Извлечение dist/Demo из .deb пакета
echo "Extracting dist/Demo from .deb package..."
mkdir -p target/dist/deb_contents
dpkg-deb -x target/dist/Demo-1.0-SNAPSHOT.deb target/dist/deb_contents
if [ $? -ne 0 ]; then
    echo "Failed to extract .deb package!"
    exit 1
fi
if [ -f "target/dist/deb_contents/opt/Demo/Demo" ]; then
    mv target/dist/deb_contents/opt/Demo/Demo target/dist/
    chmod +x target/dist/Demo
    echo "dist/Demo extracted successfully."
else
    echo "dist/Demo not found in .deb package. Checking contents of .deb package..."
    find target/dist/deb_contents -type f
    exit 1
fi
rm -rf target/dist/deb_contents

# Копирование зависимостей в dist/libs
if [ -d "target/libs" ]; then
    echo "Copying dependencies to dist/libs..."
    mkdir -p target/dist/libs
    cp target/libs/*.jar target/dist/libs/
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
tar -czf Demo.tar.gz -C target dist
if [ $? -ne 0 ]; then
    echo "Failed to create archive!"
    exit 1
fi

echo "Build completed successfully!"