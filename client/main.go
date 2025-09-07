package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"time"

	pb "github.com/day0ops/simple-ping-pong-grpc/client/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	// Get server address from environment variable
	serverAddr := os.Getenv("SERVER_ADDR")
	if serverAddr == "" {
		serverAddr = "grpc-server.default.svc.cluster.local:50051"
	}

	log.Printf("Attempting to connect to server: %s", serverAddr)

	// Perform DNS resolution test
	testDNSResolution(serverAddr)

	// Connect to the gRPC server
	conn, err := grpc.Dial(serverAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer conn.Close()

	client := pb.NewTestServiceClient(conn)

	// Test ping
	log.Println("Testing Ping...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pingResp, err := client.Ping(ctx, &pb.PingRequest{
		Message: fmt.Sprintf("Hello from client at %s", time.Now().Format(time.RFC3339)),
	})
	if err != nil {
		log.Fatalf("Ping failed: %v", err)
	}

	log.Printf("Ping Response:")
	log.Printf("  Message: %s", pingResp.Message)
	log.Printf("  Server Hostname: %s", pingResp.ServerHostname)
	log.Printf("  Server IP: %s", pingResp.ServerIp)
	log.Printf("  Timestamp: %d", pingResp.Timestamp)

	// Test host info
	log.Println("\nTesting GetHostInfo...")
	hostResp, err := client.GetHostInfo(ctx, &pb.HostRequest{})
	if err != nil {
		log.Fatalf("GetHostInfo failed: %v", err)
	}

	log.Printf("Host Info Response:")
	log.Printf("  Hostname: %s", hostResp.Hostname)
	log.Printf("  IP Address: %s", hostResp.IpAddress)
	log.Printf("  DNS Servers: %v", hostResp.DnsServers)

	log.Println("\n✅ All tests completed successfully!")
}

func testDNSResolution(serverAddr string) {
	log.Println("=== DNS Resolution Test ===")

	// Extract hostname from server address
	host := strings.Split(serverAddr, ":")[0]
	log.Printf("Resolving hostname: %s", host)

	// Perform DNS lookup
	ips, err := net.LookupIP(host)
	if err != nil {
		log.Printf("❌ DNS resolution failed: %v", err)
		return
	}

	log.Printf("✅ DNS resolution successful!")
	for _, ip := range ips {
		log.Printf("  Resolved IP: %s", ip.String())
	}

	// Test reverse DNS lookup
	if len(ips) > 0 {
		names, err := net.LookupAddr(ips[0].String())
		if err == nil && len(names) > 0 {
			log.Printf("  Reverse DNS: %v", names)
		}
	}

	// Show DNS configuration
	showDNSConfig()
	log.Println("=== End DNS Resolution Test ===\n")
}

func showDNSConfig() {
	log.Println("DNS Configuration:")
	if content, err := os.ReadFile("/etc/resolv.conf"); err == nil {
		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") {
				log.Printf("  %s", line)
			}
		}
	}
}
