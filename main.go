package main

import (
	"fmt"
	"log"
	"os"
	"strings"
)

// 常量定义：基于之前对 factory.txt 的分析
const (
	FactoryPartition = "/dev/mtd2" // Factory 分区路径

	// PCB 板级序列号
	PCBSNOffset = 0x3FF00
	PCBSNLength = 15

	// 硬件批次号/内部物料号
	BatchOffset = 0x3FF10
	BatchLength = 14

	// MAC 地址 (MAC 4)
	MAC4Offset = 0x3FFFA
	MACLength  = 6
)

// FactoryInfo 存储提取出的工厂信息
type FactoryInfo struct {
	PCBSN   string
	BatchNo string
	MAC4    string
}

// readBytes 从指定设备的特定偏移量读取指定长度的字节
func readBytes(device string, offset int64, length int) ([]byte, error) {
	// 以只读模式打开设备文件
	f, err := os.Open(device)
	if err != nil {
		return nil, fmt.Errorf("打开设备 %s 失败: %w", device, err)
	}
	defer f.Close()

	// Seek 到指定偏移量
	_, err = f.Seek(offset, os.SEEK_SET)
	if err != nil {
		return nil, fmt.Errorf("寻址到 0x%X 失败: %w", offset, err)
	}

	// 读取数据
	buf := make([]byte, length)
	n, err := f.Read(buf)
	if err != nil {
		return nil, fmt.Errorf("读取数据失败: %w", err)
	}
	if n != length {
		return nil, fmt.Errorf("读取长度不匹配: 期望 %d 字节, 实际 %d 字节", length, n)
	}

	return buf, nil
}

// GetFactoryInfo 提取并格式化所有工厂信息
func GetFactoryInfo() (*FactoryInfo, error) {
	info := &FactoryInfo{}

	// 1. 读取 PCB SN (ASCII 编码，直接转字符串)
	pcbSnBytes, err := readBytes(FactoryPartition, PCBSNOffset, PCBSNLength)
	if err != nil {
		return nil, fmt.Errorf("读取 PCB SN 失败: %w", err)
	}
	// 去除可能存在的末尾空字符或 0xFF
	info.PCBSN = strings.TrimRight(string(pcbSnBytes), "\x00\xff")

	// 2. 读取 硬件批次号 (ASCII 编码，直接转字符串)
	batchBytes, err := readBytes(FactoryPartition, BatchOffset, BatchLength)
	if err != nil {
		return nil, fmt.Errorf("读取批次号失败: %w", err)
	}
	info.BatchNo = strings.TrimRight(string(batchBytes), "\x00\xff")

	// 3. 读取 MAC 地址 (二进制字节流，需格式化为 XX:XX:XX:XX:XX:XX)
	macBytes, err := readBytes(FactoryPartition, MAC4Offset, MACLength)
	if err != nil {
		return nil, fmt.Errorf("读取 MAC 失败: %w", err)
	}
	// 将 []byte 格式化为 MAC 地址字符串
	info.MAC4 = fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X",
		macBytes[0], macBytes[1], macBytes[2],
		macBytes[3], macBytes[4], macBytes[5])

	return info, nil
}

func main() {
	info, err := GetFactoryInfo()
	if err != nil {
		log.Fatalf("错误: %v\n", err)
	}

	fmt.Println("--- OpenWrt Factory Info ---")
	fmt.Printf("PCB 板级序列号 (PCB SN)  : %s\n", info.PCBSN)
	fmt.Printf("硬件批次号/内部物料号    : %s\n", info.BatchNo)
	fmt.Printf("MAC 地址 (MAC 4)         : %s\n", info.MAC4)
}

//编译命令：
//CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -ldflags="-s -w" -o factory_reader main.go
