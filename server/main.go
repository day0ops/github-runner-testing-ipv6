package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"time"

	pb "github.com/day0ops/simple-ping-pong-grpc/server/proto"
	"google.golang.org/grpc"
)

type server struct {
	pb.UnimplementedTestServiceServer
}

func (s *server) Ping(ctx context.Context, req *pb.PingRequest) (*pb.PingResponse, error) {
	hostname, _ := os.Hostname()

	// Get server IP
	conn, err := net.Dial("udp", "8.8.8.8:80")
	var serverIP string
	if err == nil {
		defer conn.Close()
		localAddr := conn.LocalAddr().(*net.UDPAddr)
		serverIP = localAddr.IP.String()
	} else {
		serverIP = "unknown"
	}

	log.Printf("Received ping from client: %s", req.Message)

	return &pb.PingResponse{
		Message:        fmt.Sprintf("Pong! Received: %s", req.Message),
		ServerHostname: hostname,
		ServerIp:       serverIP,
		Timestamp:      time.Now().Unix(),
	}, nil
}

func (s *server) GetHostInfo(ctx context.Context, req *pb.HostRequest) (*pb.HostResponse, error) {
	hostname, _ := os.Hostname()

	// Get server IP
	conn, err := net.Dial("udp", "8.8.8.8:80")
	var serverIP string
	if err == nil {
		defer conn.Close()
		localAddr := conn.LocalAddr().(*net.UDPAddr)
		serverIP = localAddr.IP.String()
	} else {
		serverIP = "unknown"
	}

	// Get DNS servers from /etc/resolv.conf
	dnsServers := []string{}
	if content, err := os.ReadFile("/etc/resolv.conf"); err == nil {
		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "nameserver") {
				parts := strings.Fields(line)
				if len(parts) >= 2 {
					dnsServers = append(dnsServers, parts[1])
				}
			}
		}
	}

	return &pb.HostResponse{
		Hostname:   hostname,
		IpAddress:  serverIP,
		DnsServers: dnsServers,
	}, nil
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "50051"
	}

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterTestServiceServer(s, &server{})

	log.Printf("Server listening on port %s", port)
	log.Printf("Hostname: %s", func() string { h, _ := os.Hostname(); return h }())

	if err := s.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
